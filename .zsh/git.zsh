get_github_url() {
  local query="$1"

  if [[ -z "$query" ]]; then
    echo "Usage: github_url <filename (partial or full)>"
    return 1
  fi

  if ! git rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    echo "Error: Not inside a Git repository."
    return 1
  fi

  local matches
  matches=$(git ls-files | grep -i "$query")

  if [[ -z "$matches" ]]; then
    echo "Error: No matching files found for '$query'."
    return 1
  fi

  local file
  if echo "$matches" | grep -q "^"; then
    if [[ $(echo "$matches" | wc -l) -gt 1 ]]; then
      echo "Multiple matches found:"
      echo "$matches" | nl -w2 -s'. '
      echo "Enter the number of the file you want:"
      read -r choice
      file=$(echo "$matches" | sed -n "${choice}p")
    else
      file="$matches"
    fi
  fi

  if [[ -z "$file" ]]; then
    echo "Error: No file selected."
    return 1
  fi

  local remote_url
  remote_url=$(git config --get remote.origin.url)
  if [[ -z "$remote_url" ]]; then
    echo "Error: No remote origin URL found."
    return 1
  fi

  remote_url=${remote_url/git@github.com:/https://github.com/}
  remote_url=${remote_url/.git/}

  local branch
  branch=$(git symbolic-ref --short HEAD)

  local github_url="${remote_url}/blob/${branch}/${file}"
  echo "$github_url" | pbcopy
  echo "$github_url"
}

# ─── Landed-proof: the ONE predicate every destructive path in this file uses ──
#
# "Is it safe to destroy this branch?" has exactly one right answer: YES only when
# the work is PROVABLY on origin. Every other predicate this file has carried —
# `[gone]`, "no worktree", "no open PR", "older than 2h" — is the ABSENCE of a
# signal, and absence is not proof. Each one destroyed real work (RVT-2881,
# RVT-2886).
#
# It lives in one place because it used to live in four, and they disagreed. Two
# predicates answering the same safety question is how the 2026-07-13 two-step
# existed at all: one tool's "safe" was another tool's "in use".
#
# Preflight resolves the shared facts once. Echoes "<default>\t<gh_ok>"; returns
# non-zero — meaning DELETE NOTHING — if origin cannot be seen or named.
_git_landed_preflight() {
  local label="${1:-prune}"

  # Without a fresh view of origin we cannot prove anything landed.
  if ! git fetch --prune >/dev/null 2>&1; then
    echo "$label: 'git fetch --prune' FAILED — refusing to delete anything." >&2
    echo "  (cannot prove what landed without a current view of origin; fail closed)" >&2
    return 1
  fi

  # The default branch is the ancestor test's reference point.
  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  if [[ -z "$default" ]] || ! git rev-parse --verify --quiet "refs/remotes/origin/$default" >/dev/null; then
    echo "$label: cannot resolve origin's default branch — refusing to delete anything." >&2
    echo "  (try: git remote set-head origin -a)" >&2
    return 1
  fi

  # gh proves the squash-merge case. Without it ordinary merges are still provable
  # via the ancestor test; squash-merged branches simply stay KEPT (fail closed).
  local gh_ok=0
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh_ok=1
  fi

  printf '%s\t%s' "$default" "$gh_ok"
}

# Is <branch> provably landed on origin? Echoes exactly one of:
#   landed
#   keep|<reason>
# Proof is positive, and only these two forms count:
#   1. the branch is an ancestor of origin/<default>              (an ordinary merge)
#   2. origin has a MERGED PR whose head is that branch           (a squash merge,
#      whose SHA necessarily differs from the local tip)
# Anything else — including EVERY error path — is `keep`. An error is not proof,
# and the error case IS the dangerous population: RVT-2881's check ran
# `git log @{u}..`, which exits 128 with EMPTY stdout on a never-pushed branch,
# and empty output was read as "nothing unpushed, safe to delete".
#
# The local-branch form: proves refs/heads/<branch>.
# Args: <branch> <default> <gh_ok>
_git_branch_landed_proof() {
  _git_ref_landed_proof "refs/heads/$1" "$1" "$2" "$3"
}

# The remote form: proves refs/remotes/origin/<branch>. Same proof, different ref —
# deleting a remote branch destroys the copy of last resort, so it gets the same
# standard, not a weaker one.
# Args: <branch> <default> <gh_ok>
_git_remote_landed_proof() {
  _git_ref_landed_proof "refs/remotes/origin/$1" "$1" "$2" "$3"
}

# Args: <ref-to-prove> <branch-name> <default> <gh_ok>
_git_ref_landed_proof() {
  local ref="$1" branch="$2" default="$3" gh_ok="$4" rc pr

  # PROOF 1 — ordinary merge: the tip is reachable from origin/<default>.
  # Exit codes: 0 = ancestor, 1 = not an ancestor, anything else = ERROR. An error
  # must never be read as "not landed, therefore examine further" — it is simply
  # not proof, so the branch is kept either way.
  git merge-base --is-ancestor "$ref" "refs/remotes/origin/$default" 2>/dev/null
  rc=$?
  if (( rc == 0 )); then
    printf 'landed'
    return 0
  elif (( rc != 1 )); then
    printf 'keep|error resolving ancestry (git exit %s) — fail closed' "$rc"
    return 0
  fi

  # PROOF 2 — squash merge: origin has a MERGED PR whose head is this branch.
  # Note "--state merged", not "not open": a CLOSED-unmerged PR is work that was
  # explicitly ABANDONED, i.e. the strongest possible signal it never landed. The
  # old verdict treated any non-OPEN PR as "captured" and force-deleted it.
  if (( ! gh_ok )); then
    printf 'keep|gh unavailable/unauthenticated, cannot prove a squash-merged PR — fail closed'
    return 0
  fi

  pr=$(gh pr list --head "$branch" --state merged --limit 1 --json number \
         --jq '.[0].number' 2>/dev/null)
  rc=$?
  if (( rc != 0 )); then
    printf 'keep|could not query origin for a merged PR — fail closed'
  elif [[ -n "$pr" && "$pr" != "null" ]]; then
    printf 'landed'
  else
    printf 'keep|not merged into origin/%s and no merged PR — unlanded work' "$default"
  fi
  return 0
}

# Delete local branches whose work has PROVABLY LANDED on origin (RVT-2886).
#
# Usage: git-prune-gone [--dry-run|-n] [--yes|-y]
#
# WHAT CHANGED, AND WHY (2026-07-13 incident)
# -------------------------------------------
# This function used to force-delete every branch whose upstream was [gone], guarded
# ONLY by a skip-list of branches checked out in a worktree. Both halves were wrong:
#
#   * `[gone]` means "the remote ref is missing". It does NOT mean "the work landed".
#     A remote branch deleted by hand — or by any tooling — on work that never merged
#     produces exactly the same [gone] as a squash-merged PR. `git branch -D` does not
#     ask, and the commits go with it.
#
#   * The worktree skip-list answered "is this branch in use", which is not the same
#     question as "is this branch safe to destroy". Worse, it made removing a worktree
#     silently ARM a force-delete in a tool the remover never ran — the two-step that
#     destroyed ~22 rescue worktrees and their branch refs on 2026-07-13.
#
#     It was also REDUNDANT: git itself already refuses to delete a branch checked out
#     in another worktree ("error: cannot delete branch 'x' used by worktree at ...",
#     exit 1). The skip-list was re-implementing a guarantee git enforces, while
#     substituting a wrong predicate for the one that mattered. It is DELETED, not
#     repaired — a protection registry inverts the default (things become persistent-
#     unless-listed), agents discover the exemption, and the population grows without
#     bound.
#
# THE PREDICATE IS NOW POSITIVE PROOF OF LANDING, AND NOTHING ELSE:
#
#   1. the branch is an ancestor of origin/<default>            (a normal merge), OR
#   2. origin has a MERGED pull request whose head is that branch (a squash merge,
#      whose SHA necessarily differs from the local tip).
#
# Absence of a signal is never proof. [gone], "no worktree", "no upstream" — none of
# them mean the work is safe to destroy.
#
# FAIL CLOSED. Any error resolving remote state means we do NOT delete. This is the
# direct lesson of RVT-2881, whose safety check ran `git log @{u}..` — which exits 128
# with EMPTY STDOUT on a never-pushed branch, and empty output was read as "nothing
# unpushed, safe to delete". The error case IS the dangerous population.
#
# THE LIST SHOWN IS THE LIST DELETED. Every branch is named before anything is removed,
# and deletion iterates that exact list. (The old code printed the SKIPPED branches and
# never printed what it was about to destroy.)
git-prune-gone() {
  local dry_run=0 assume_yes=0
  while (( $# )); do
    case "$1" in
      -n|--dry-run) dry_run=1 ;;
      -y|--yes)     assume_yes=1 ;;
      -h|--help)
        echo "usage: git-prune-gone [--dry-run|-n] [--yes|-y]"
        echo "  Deletes local branches PROVEN landed on origin (merged, or a merged PR)."
        echo "  Anything unproven — including any error resolving remote state — is KEPT."
        return 0
        ;;
      *) echo "git-prune-gone: unknown option '$1'" >&2; return 2 ;;
    esac
    shift
  done

  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "git-prune-gone: not a git repository." >&2
    return 1
  }

  # Fail closed: no view of origin, or no name for the default branch → delete nothing.
  local preflight default gh_ok
  preflight=$(_git_landed_preflight git-prune-gone) || return 1
  IFS=$'\t' read -r default gh_ok <<< "$preflight"

  local -a landed keep_reasons
  local branch verdict

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    [[ "$branch" == "$default" ]] && continue

    verdict=$(_git_branch_landed_proof "$branch" "$default" "$gh_ok")
    if [[ "$verdict" == "landed" ]]; then
      landed+=("$branch")
    else
      keep_reasons+=("$branch|KEPT: ${verdict#keep|}")
    fi
  done < <(git for-each-ref --format '%(refname:short)' refs/heads)

  if (( ${#keep_reasons[@]} )); then
    echo "Kept (not proven landed):"
    local entry
    for entry in "${keep_reasons[@]}"; do
      printf '  %-45s %s\n' "${entry%%|*}" "${entry#*|}"
    done
  fi

  if (( ${#landed[@]} == 0 )); then
    echo "Nothing proven landed. No branches deleted."
    return 0
  fi

  # THE LIST SHOWN IS THE LIST DELETED — printed before anything is destroyed, and the
  # deletion loop below iterates this exact array.
  echo "Will DELETE ${#landed[@]} branch(es) proven landed on origin:"
  local b
  for b in "${landed[@]}"; do
    printf '  %-45s %s\n' "$b" "$(git rev-parse --short "refs/heads/$b" 2>/dev/null)"
  done

  if (( dry_run )); then
    echo "--dry-run: nothing deleted."
    return 0
  fi

  if (( ! assume_yes )); then
    local reply
    read -q "reply?Delete these ${#landed[@]} branch(es)? [y/N] "
    echo
    if [[ "$reply" != [yY] ]]; then
      echo "Aborted. Nothing deleted."
      return 0
    fi
  fi

  # If HEAD is on one of them, step off first — otherwise git refuses and we would
  # report a deletion that did not happen.
  local current
  current=$(git symbolic-ref --short HEAD 2>/dev/null)
  for b in "${landed[@]}"; do
    if [[ "$b" == "$current" ]]; then
      echo "Switching off '$current' to '$default' before deletion..."
      git switch "$default" || {
        echo "git-prune-gone: could not switch off '$current' — nothing deleted." >&2
        return 1
      }
      break
    fi
  done

  # Delete one at a time so each outcome is reported against the branch it belongs to.
  # A branch checked out in another worktree fails here — git's own guarantee, and the
  # reason the skip-list was never what protected it.
  for b in "${landed[@]}"; do
    if git branch -D "$b" >/dev/null 2>&1; then
      echo "  deleted  $b"
    else
      echo "  FAILED   $b (still checked out in a worktree, or ref locked)"
    fi
  done
  return 0
}

# Resolve a PR's state + mergeability, polling while GitHub recomputes it.
# Immediately after a push or PR-open GitHub returns mergeable=UNKNOWN for a few
# seconds; this retries instead of bailing on that transient state.
# Tunable via GIT_PR_MERGEABLE_RETRIES (default 5) and GIT_PR_MERGEABLE_DELAY
# (default 3 seconds between attempts).
#
# Usage:   _git_pr_mergeability [<pr-number>]   (empty arg → current branch's PR)
# Echoes:  "<state> <mergeable>" on stdout (mergeable may still be UNKNOWN if it
#          never resolved within the retry budget — callers decide what to do).
# Returns: 0 when gh resolved the PR; 1 when `gh pr view` failed (PR not found).
_git_pr_mergeability() {
  local pr="$1"
  local -a view_args=(--json state,mergeable -q '.state + " " + .mergeable')
  [[ -n "$pr" ]] && view_args=("$pr" "${view_args[@]}")

  local attempts="${GIT_PR_MERGEABLE_RETRIES:-5}"
  local delay="${GIT_PR_MERGEABLE_DELAY:-3}"
  local label="${pr:+#$pr}"; : "${label:=for current branch}"
  local info state mergeable i
  for (( i = 1; i <= attempts; i++ )); do
    info=$(gh pr view "${view_args[@]}" 2>/dev/null) || return 1
    read -r state mergeable <<< "$info"
    if [[ "$mergeable" != "UNKNOWN" ]]; then
      echo "$state $mergeable"
      return 0
    fi
    (( i < attempts )) || break
    echo "PR $label mergeability still computing on GitHub; retrying in ${delay}s (attempt $i/$attempts)..." >&2
    sleep "$delay"
  done

  # Retry budget exhausted, still UNKNOWN — hand it back so the caller errors/skips.
  echo "$state $mergeable"
  return 0
}

# Merge a PR — or every open PR — by squash-admin, clean up that PR's related
# branches + worktrees (patch-id scoped), then optionally sweep global orphans.
# Single entry point; wraps the scoped merge engine (_git_merge_pr_clean_scoped).
#
# Modes:
#   git-merge-pr-clean              — derive the PR from the current branch
#   git-merge-pr-clean <pr-number>  — merge a specific PR
#   git-merge-pr-clean --all        — merge every open PR (skips CONFLICTING/UNKNOWN);
#                                     pulls the default branch ONCE after all merges,
#                                     so post-pull git hooks run once, not per-PR
#
# From a feature branch the PR number is captured BEFORE switching to the default
# branch (afterwards gh would resolve the default branch's non-existent PR). If
# invoked from a secondary worktree, we cd to the main worktree first — the default
# branch can't be checked out in two worktrees. The scoped engine then removes each
# merged PR's related worktrees + branches.
#
# Post-merge global orphan sweep (on top of the per-PR scoped cleanup):
#   -l   also run `git-prune-orphans`    (local orphans + stale worktrees)
#   -r   also run `git-prune-orphans -r` (remote no-PR branches, 6h-gated + local)
#   -R   alias for -r (single remote mode)
# -l is implied by -r/-R.
#
#   --dry-run   preview only — no switch, no merge, no delete. Read-only.
#
# In --all mode extra args forward to `gh pr list` (e.g. --author=@me, --label foo).
git-merge-pr-clean() {
  local all=0 prune_local=0 prune_remote_mode="" dry_run=0 pr_arg=""
  local -a extra=() gh_args=()
  while (( $# > 0 )); do
    case "$1" in
      --all)     all=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      -l)              prune_local=1; shift ;;
      -r|-R)           prune_remote_mode="safe"; shift ;;
      -lr|-rl|-lR|-Rl) prune_local=1; prune_remote_mode="safe"; shift ;;
      *)         extra+=("$1"); shift ;;
    esac
  done

  # Resolve trailing args: --all → gh pr list filters; else a single PR number.
  if (( all )); then
    gh_args=("${extra[@]}")
  else
    local a
    for a in "${extra[@]}"; do
      [[ "$a" == -* ]] && { echo "Error: unknown flag '$a'" >&2; return 2; }
      [[ -n "$pr_arg" ]] && { echo "Error: multiple positional args (already have '$pr_arg')" >&2; return 2; }
      pr_arg="$a"
    done
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: not in a git repo" >&2; return 1; }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  # ── Dry run: read-only preview, never switches branches ──────────────────────
  if (( dry_run )); then
    if (( all )); then
      local prs pr
      prs=$(gh pr list --state open --json number --jq '.[].number' "${gh_args[@]}" 2>/dev/null | sort -n)
      if [[ -z "$prs" ]]; then
        echo "No open PRs."
      else
        while IFS= read -r pr; do
          [[ -z "$pr" ]] && continue
          _git_merge_pr_clean_scoped "$pr" --dry-run
        done <<< "$prs"
      fi
    else
      local pr="$pr_arg"
      if [[ -z "$pr" ]]; then
        pr=$(gh pr view --json number -q .number 2>/dev/null) \
          || { echo "Error: no PR found for current branch" >&2; return 1; }
      fi
      _git_merge_pr_clean_scoped "$pr" --dry-run || return 1
    fi
    case "$prune_remote_mode" in
      safe) git-prune-orphans -R --dry-run ;;
      "")   (( prune_local )) && git-prune-orphans --dry-run ;;
    esac
    return 0
  fi

  # ── Live: switch to the default branch (in the main worktree), then merge ────
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || { echo "Error: detached HEAD" >&2; return 1; }

  local pr="$pr_arg"
  if (( ! all )) && [[ -z "$pr" ]]; then
    # Single mode, no explicit PR: derive it from the current branch first.
    if [[ "$branch" == "$default" ]]; then
      echo "Error: on default branch '$default' — pass a PR number or switch to a feature branch" >&2
      return 1
    fi
    pr=$(gh pr view --json number -q .number 2>/dev/null) || pr=""
    [[ -z "$pr" ]] && { echo "Error: no PR found for '$branch'" >&2; return 1; }
    local upstream ahead
    upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
    if [[ -n "$upstream" ]]; then
      ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)
      (( ahead > 0 )) && { echo "Error: $ahead unpushed commit(s) on '$branch'. Push before merging." >&2; return 1; }
    fi
  fi

  # Switch to the default branch in the main worktree before invoking the engine.
  if [[ "$branch" != "$default" ]]; then
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
      echo "Error: uncommitted changes on '$branch'; commit or stash first" >&2; return 1
    fi
    if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
      echo "Error: untracked files on '$branch'; commit, stash, or clean first" >&2; return 1
    fi
    local current_wt main_wt
    current_wt=$(git rev-parse --show-toplevel)
    main_wt=$(git worktree list --porcelain | awk '/^worktree / {print $2; exit}')
    if [[ "$current_wt" != "$main_wt" ]]; then
      echo "==> Secondary worktree detected; switching to main at $main_wt"
      cd "$main_wt" || return 1
    fi
    echo "==> Switching to '$default' (was on '$branch')"
    git checkout "$default" || return 1
  fi

  if (( all )); then
    local prs merged=0 skipped=0 p
    prs=$(gh pr list --state open --json number --jq '.[].number' "${gh_args[@]}" 2>/dev/null | sort -n) \
      || { echo "Error: gh pr list failed" >&2; return 1; }
    if [[ -z "$prs" ]]; then
      echo "Error: no open PRs to merge." >&2
      return 1
    fi
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      echo "==> PR #$p"
      if _git_merge_pr_clean_scoped "$p" --no-pull; then
        merged=$((merged + 1))
      else
        echo "PR #$p: scoped merge/cleanup failed — skipping" >&2
        skipped=$((skipped + 1))
      fi
    done <<< "$prs"
    echo "==> Merged $merged PR(s)$( (( skipped > 0 )) && echo "; $skipped skipped" )."
    # Single pull after all merges — repos with post-pull git hooks run them once
    # instead of once per PR. Skipped if nothing merged (no remote movement).
    if (( merged > 0 )); then
      echo "==> Pulling '$default' once after $merged merge(s)"
      git pull || return 1
    fi
  else
    _git_merge_pr_clean_scoped "$pr" || return 1
  fi

  # ── Post-merge global orphan sweep ───────────────────────────────────────────
  case "$prune_remote_mode" in
    safe) git-prune-orphans -R ;;
    "")   (( prune_local )) && git-prune-orphans ;;
  esac
}

# Print branches "related to" a specific PR — the PR head branch plus any local
# branches whose unique commits appear (by patch-id) in the PR head branch's
# history. Read-only; emits one branch name per line, head branch first.
#
# Independence from cherry-pick `-x` markers: discovery is by patch-id, so it
# catches cherry-picks made without `-x` AND cross-checks `-x`-marked ones.
#
# Usage:
#   _git_pr_related_branches <pr-number>
_git_pr_related_branches() {
  local pr="$1"
  if [[ -z "$pr" ]]; then
    echo "Usage: _git_pr_related_branches <pr-number>" >&2
    return 2
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local session_branch
  session_branch=$(gh pr view "$pr" --json headRefName -q .headRefName 2>/dev/null) || {
    echo "Error: PR #$pr not found" >&2
    return 1
  }
  if [[ -z "$session_branch" ]]; then
    echo "Error: PR #$pr has no head branch" >&2
    return 1
  fi

  # If the session branch isn't local (e.g. fork PR), there's nothing to trace.
  if ! git rev-parse --verify --quiet "refs/heads/$session_branch" >/dev/null; then
    echo "$session_branch"
    return 0
  fi

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  local mb
  mb=$(git merge-base "$session_branch" "$default" 2>/dev/null)
  if [[ -z "$mb" ]]; then
    echo "Error: no merge-base between '$session_branch' and '$default'" >&2
    return 1
  fi

  # Patch-ids of commits unique to the session branch vs default.
  local session_pids
  session_pids=$(git log -p --no-merges "$mb..$session_branch" 2>/dev/null \
                 | git patch-id --stable 2>/dev/null \
                 | awk '{print $1}' | sort -u)

  # No unique commits — emit just the session branch; cleanup still applies.
  if [[ -z "$session_pids" ]]; then
    echo "$session_branch"
    return 0
  fi

  # For every other local branch, see if any of its unique commits share a
  # patch-id with a session-branch commit. With <50 branches this is fast.
  local agents="" branch other_mb branch_pids overlap
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    [[ "$branch" == "$session_branch" ]] && continue
    [[ "$branch" == "$default" ]] && continue

    other_mb=$(git merge-base "$branch" "$default" 2>/dev/null)
    [[ -z "$other_mb" ]] && continue

    branch_pids=$(git log -p --no-merges "$other_mb..$branch" 2>/dev/null \
                  | git patch-id --stable 2>/dev/null \
                  | awk '{print $1}' | sort -u)
    [[ -z "$branch_pids" ]] && continue

    overlap=$(comm -12 <(echo "$session_pids") <(echo "$branch_pids"))
    if [[ -n "$overlap" ]]; then
      agents+="$branch"$'\n'
    fi
  done < <(git for-each-ref --format='%(refname:short)' refs/heads)

  echo "$session_branch"
  [[ -n "$agents" ]] && printf '%s' "$agents"
  return 0
}

# Merge a specific PR (admin override), then clean up ONLY the branches and
# worktrees related to that PR — the PR head branch plus any local branches
# whose commits cherry-picked into it (discovered by patch-id, no `-x`
# required). Other concurrent sessions' worktrees/branches are left untouched
# by construction.
#
# Designed for the case where multiple Claude sessions share a repo: existing
# global pruners (git-prune-gone, _git_prune_local_orphans) would reap state
# belonging to OTHER live sessions; this command stays scoped to one PR.
#
# Usage:
#   _git_merge_pr_clean_scoped <pr-number>            — merge and clean
#   _git_merge_pr_clean_scoped <pr-number> --dry-run  — print plan; no merge, no delete
# Internal engine for git-merge-pr-clean; not a standalone command.
_git_merge_pr_clean_scoped() {
  local dry_run=0 no_pull=0 pr=""
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
      --no-pull) no_pull=1; shift ;;
      -*) echo "Error: unknown flag '$1'" >&2; return 2 ;;
      *)
        if [[ -n "$pr" ]]; then
          echo "Error: multiple positional args (already have '$pr')" >&2
          return 2
        fi
        pr="$1"; shift ;;
    esac
  done

  if [[ -z "$pr" ]]; then
    echo "Usage: _git_merge_pr_clean_scoped <pr-number> [--dry-run]" >&2
    return 2
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  # The default-branch guard is a merge-safety check; dry-run is read-only and may
  # run from the feature branch (so the unified entry can preview without switching).
  if (( ! dry_run )); then
    local current
    current=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [[ "$current" != "$default" ]]; then
      echo "Error: must be on default branch '$default' (current: '$current')" >&2
      return 1
    fi
  fi

  # Validate PR state up front (skipped in dry-run only if PR is closed/merged —
  # still useful to preview which branches the cleanup would touch).
  local pr_info pr_state pr_mergeable
  pr_info=$(_git_pr_mergeability "$pr") || {
    echo "Error: PR #$pr not found" >&2
    return 1
  }
  read -r pr_state pr_mergeable <<< "$pr_info"

  if (( ! dry_run )); then
    if [[ "$pr_state" != "OPEN" ]]; then
      echo "Error: PR #$pr is $pr_state (not OPEN)" >&2
      return 1
    fi
    if [[ "$pr_mergeable" == "CONFLICTING" ]]; then
      echo "Error: PR #$pr has merge conflicts. Resolve before merging." >&2
      return 1
    fi
    if [[ "$pr_mergeable" == "UNKNOWN" ]]; then
      echo "Error: PR #$pr mergeability still computing on GitHub after retries. Try again shortly." >&2
      return 1
    fi
  fi

  # Discover related branches BEFORE merging so the session branch's commits
  # are still distinct from default — post-merge the patch-id trace would be
  # noisy or empty.
  local related
  related=$(_git_pr_related_branches "$pr") || return 1
  if [[ -z "$related" ]]; then
    echo "Error: no related branches discovered for PR #$pr" >&2
    return 1
  fi

  echo "==> Related branches for PR #$pr:"
  echo "$related" | sed 's/^/  /'

  # Pre-resolve worktree info so dry-run can print accurate paths.
  local wt_info main_wt
  wt_info=$(git worktree list --porcelain)
  main_wt=$(echo "$wt_info" | awk '/^worktree / { print $2; exit }')

  if (( dry_run )); then
    echo
    echo "==> Worktrees that would be removed:"
    local any_wt=0 branch wt_path locked
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      read -r wt_path locked < <(echo "$wt_info" | awk -v b="refs/heads/$branch" '
        BEGIN { RS = ""; FS = "\n" }
        {
          path = ""; br = ""; lk = 0
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^worktree /) path = substr($i, 10)
            else if ($i ~ /^branch /) br = substr($i, 8)
            else if ($i ~ /^locked/) lk = 1
          }
          if (br == b) { print path, lk; exit }
        }')
      if [[ -n "$wt_path" && "$wt_path" != "$main_wt" ]]; then
        if _git_worktree_is_live "$wt_path" "$locked" 0; then
          echo "  $branch  ($wt_path) [live — would be SKIPPED: uncommitted work or locked]"
        else
          any_wt=1
          echo "  $branch  ($wt_path)$([[ "$locked" == "1" ]] && echo ' [locked]')"
        fi
      fi
    done <<< "$related"
    (( any_wt )) || echo "  (none)"
    echo
    echo "Dry run: would merge PR #$pr (state=$pr_state mergeable=$pr_mergeable), then delete the above worktrees + all listed branches."
    return 0
  fi

  # Merge.
  echo
  echo "==> Merging PR #$pr"
  gh pr merge "$pr" -s --admin || return 1
  # --no-pull defers the pull to a single post-loop pull in --all mode (so repos
  # with post-pull git hooks run them once, not once per PR). Branch/worktree
  # cleanup below doesn't depend on the local default being pulled.
  if (( ! no_pull )); then
    git pull || return 1
  fi

  # Cleanup: for each related branch, remove its worktree (unlocking if needed)
  # then delete the branch. Failures are logged but don't abort — partial
  # cleanup is still progress.
  echo
  echo "==> Cleaning up related branches and worktrees:"
  local branch wt_path locked verdict deleted=0 wt_removed=0 failed=0
  # The landed-proof check below needs a current view of origin (the merge just
  # happened) and gh for the squash-merge case. `gh pr merge --squash` is exactly
  # the case the ancestor test cannot see, so without gh nothing here is provable
  # and every branch is skipped — loudly, and with its worktree left in place.
  local gh_ok=0
  git fetch --prune >/dev/null 2>&1 || true
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh_ok=1
  fi
  # Refresh worktree info post-merge in case anything shifted.
  wt_info=$(git worktree list --porcelain)
  main_wt=$(echo "$wt_info" | awk '/^worktree / { print $2; exit }')
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    read -r wt_path locked < <(echo "$wt_info" | awk -v b="refs/heads/$branch" '
      BEGIN { RS = ""; FS = "\n" }
      {
        path = ""; br = ""; lk = 0
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^worktree /) path = substr($i, 10)
          else if ($i ~ /^branch /) br = substr($i, 8)
          else if ($i ~ /^locked/) lk = 1
        }
        if (br == b) { print path, lk; exit }
      }')

    # Live-worktree guard: never force-remove a worktree with uncommitted work
    # or an explicit lock, even for this PR's own just-merged branch — that would
    # discard an agent's in-flight edits. Skip the branch delete too (git refuses
    # to delete a branch checked out in a live worktree anyway).
    if [[ -n "$wt_path" && "$wt_path" != "$main_wt" ]] \
       && _git_worktree_is_live "$wt_path" "$locked" 0; then
      echo "Skipping live worktree + branch (uncommitted work or locked): $branch ($wt_path)" >&2
      continue
    fi

    if [[ -n "$wt_path" && "$wt_path" != "$main_wt" ]]; then
      # No unlock, and no --force. The live guard above already skips locked and
      # dirty worktrees, so the unlock branch that used to sit here was a loaded
      # gun behind a safety catch: unreachable today, re-armed by the next refactor
      # of that guard. `git worktree remove` (unforced) refusing a dirty tree is a
      # real second net; --force existed only to defeat it. See RVT-2881.
      echo "Removing worktree: $wt_path"
      if ! git worktree remove "$wt_path"; then
        echo "  SKIP $branch — could not remove its worktree $wt_path" >&2
        failed=$((failed + 1))
        continue
      fi
      wt_removed=$((wt_removed + 1))
    fi

    # Proof, not assumption. `$related` is "the PR head plus branches whose commits
    # patch-id-match it" — a heuristic for "this landed with the PR", and a heuristic
    # is not proof. Ask the same question every other destructive path in this file
    # now asks, and skip anything that cannot answer it.
    verdict=$(_git_branch_landed_proof "$branch" "$default" "$gh_ok")
    if [[ "$verdict" != "landed" ]]; then
      echo "  SKIP $branch — ${verdict#keep|}" >&2
      failed=$((failed + 1))
      continue
    fi

    echo "Deleting branch: $branch"
    if git branch -D "$branch" 2>/dev/null; then
      deleted=$((deleted + 1))
    else
      echo "  failed to delete branch $branch" >&2
      failed=$((failed + 1))
    fi
  done <<< "$related"

  echo "==> Removed $wt_removed worktree(s), deleted $deleted branch(es)$( (( failed > 0 )) && echo "; $failed failure(s)" )."
}

# ─── Orphan pruning ──────────────────────────────────────────────────────────
#
# Unified entry point + primitives. Default: local only (safe in shared repos —
# never touches origin, so other engineers' branches are preserved).
#
# Deletion policy — ONE predicate, everywhere: POSITIVE PROOF OF LANDING (RVT-2886).
#   1. A branch (local or remote) is deletable ONLY if its work is PROVEN to be on
#      origin: merged into origin/<default>, or carried by a MERGED PR. See
#      _git_branch_landed_proof. Every error path keeps.
#   2. Nothing else is proof. Not "no open PR", not "the remote ref is [gone]", not
#      "older than N hours", not "no worktree holds it". Each of those is the
#      ABSENCE of a signal, each one shipped here, and each one destroyed real work.
#   3. AGE survives in exactly one place, because there it is the only thing left:
#      DETACHED worktrees carry no branch ref, so landing cannot be proved or
#      disproved. GIT_PRUNE_MIN_AGE (default 7200 = 2h) gates those alone.
#   4. REMOTE (`-r`) additionally holds proven-landed branches for
#      GIT_PRUNE_REMOTE_MIN_AGE (default 21600 = 6h) — proof is necessary, and on
#      shared state the age window is a second hold on top of it.
#   5. A LOCKED worktree is never touched, at any age, under any flag. Nothing in
#      this file calls `git worktree unlock`.
#
#   git-prune-orphans          — UNIFIED entry point. Default = local only.
#                                -r → remote (proven-landed, 6h-gated) THEN local.
#   _git_remote_orphans         — LIST remote branches on origin with no open PR
#   _git_prune_remote_orphans   — DELETE proven-landed, 6h-aged remote branches
#   _git_local_orphans          — LIST local branches with no corresponding remote
#   _git_prune_local_orphans    — DELETE proven-landed local orphans AND the
#                                worktrees that hold them; protects open-PR and
#                                within-grace WIP. Never touches origin.
#   git-sync                    — pull --ff-only + fetch --tags + local prune
#
# ─────────────────────────────────────────────────────────────────────────────

# Resolve the repo's default branch (origin/HEAD), falling back to "master".
_git_default_branch() {
  local d
  d=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  echo "${d:-master}"
}

# _git_capture_ref is DELETED with the verdict function that was its only caller.
# It fell back to the LOCAL <default> branch when origin/<default> was missing — so
# with an unfetchable origin, "merged" was judged against a possibly-stale local
# master, and a branch could be declared captured against a ref that had itself
# never landed. Proof is now taken against refs/remotes/origin/<default> or not at
# all: if origin cannot be seen, _git_landed_preflight fails and nothing is deleted.

# Grace window (seconds) before an unprovable DETACHED worktree is prunable.
_git_prune_min_age() { echo "${GIT_PRUNE_MIN_AGE:-7200}"; }

# Grace window (seconds) before a no-PR REMOTE branch is prunable — longer than
# local, since the remote is shared with other engineers (default 21600 = 6h).
_git_prune_remote_min_age() { echo "${GIT_PRUNE_REMOTE_MIN_AGE:-21600}"; }

# Age in seconds of a ref's last commit (empty on failure).
_git_ref_age_secs() {
  local ct
  ct=$(git log -1 --format=%ct "$1" 2>/dev/null) || return 1
  [[ -z "$ct" ]] && return 1
  echo $(( $(date +%s) - ct ))
}

# Return 0 (LIVE — protect) if a secondary worktree looks like an active session
# whose directory/uncommitted work must NOT be force-removed:
#   - locked          → the operator/agent explicitly marked it hands-off
#   - dirty tree      → uncommitted work a force-remove would silently discard
#   - young HEAD      → last commit within the local grace window (an agent that
#                       just committed/merged and is likely still live)
# Return 1 (safe to reap) otherwise. This is the guard that makes the grace
# window govern *captured* worktrees too — a merged-PR branch checked out in a
# live worktree is captured (no grace by branch verdict), but must still be
# protected while the agent is running.
#
# Args: <worktree-path> <locked 0|1> [<check_age 0|1>, default 1]
# check_age=0 skips the young-HEAD test — used by explicit `git-merge-pr-clean`,
# where a freshly-merged (young) branch is exactly what SHOULD be cleaned up; the
# lock/dirty protections still apply so uncommitted work is never discarded.
_git_worktree_is_live() {
  local wt="$1" locked="$2" check_age="${3:-1}"
  [[ "$locked" == "1" ]] && return 0

  # FAIL CLOSED on the dirty check. `git status` writes NOTHING to stdout when it
  # ERRORS (missing path, broken gitdir, unreadable tree) — identical output to a
  # perfectly clean tree. Testing only for empty stdout read "I could not look" as
  # "there is nothing there", which is the exact fail-open shape that let RVT-2881
  # delete live work. Cannot prove it clean => treat it as live.
  local status_out status_rc
  status_out=$(git -C "$wt" status --porcelain 2>/dev/null)
  status_rc=$?
  (( status_rc != 0 )) && return 0
  [[ -n "$status_out" ]] && return 0

  if (( check_age )); then
    local ct min
    ct=$(git -C "$wt" log -1 --format=%ct HEAD 2>/dev/null)
    # Unresolvable age is not "old enough to reap" — it is unknown. Keep.
    [[ -z "$ct" ]] && return 0
    min=$(_git_prune_min_age)
    (( $(date +%s) - ct < min )) && return 0
  fi
  return 1
}

# _git_pr_branch_states and _git_branch_prune_verdict are DELETED (RVT-2886).
#
# The verdict function carried a SECOND, weaker answer to "is this safe to
# destroy" while git-prune-gone carried the landed-proof answer. Two predicates
# for one safety question is how the 2026-07-13 two-step existed. Both of its
# delete verdicts were unsound, and neither was a near-miss:
#
#   deletable-old — "no PR, and the last commit is older than 2h" → `git branch -D`.
#     Age is not proof of anything. This force-deleted a NEVER-PUSHED branch with
#     unmerged commits after two hours. git-prune-gone could not even SEE that
#     branch (no upstream, so never `[gone]`) — so the everyday `git-sync`, which
#     calls this path with no preview and no confirmation, was strictly MORE
#     dangerous than the tool this ticket was filed against.
#
#   deletable-captured — treated ANY non-OPEN PR as captured, including CLOSED.
#     A closed-unmerged PR is the strongest available signal that work was
#     abandoned WITHOUT landing. It was read as permission to force-delete.
#
# Branch deletion now goes through _git_branch_landed_proof and nothing else.
# Age survives ONLY where it is honest: as a grace window on DETACHED worktrees,
# which carry no branch ref and so cannot be proof-checked at all.

# List remote branches on origin that have no open PR (and aren't the default).
# Excludes origin/HEAD and the default branch.
_git_remote_orphans() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  local remote_branches pr_branches
  remote_branches=$(git ls-remote --heads origin 2>/dev/null \
                    | awk '{sub("refs/heads/", "", $2); print $2}' \
                    | grep -vx "$default" \
                    | sort -u)

  pr_branches=$(gh pr list --state open --json headRefName -q '.[].headRefName' 2>/dev/null | sort -u)

  comm -23 <(echo "$remote_branches") <(echo "$pr_branches")
}

# List local branches that have no corresponding branch on origin.
# Includes branches that never had upstream AND branches whose upstream was deleted.
# Excludes origin/HEAD.
_git_local_orphans() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  comm -23 \
    <(git for-each-ref --format='%(refname:short)' refs/heads | sort) \
    <(git for-each-ref --format='%(refname:short)' refs/remotes/origin \
        | sed 's|^origin/||' | grep -v '^HEAD$' | sort -u)
}

# Unified orphan pruner — see § header at top of "Orphan pruning" section.
#
# Usage:
#   git-prune-orphans                  — local only (default; safe in shared repos)
#   git-prune-orphans -r               — remote (proven-landed, 6h-gated), then local
#   git-prune-orphans -f               — drop the AGE grace on detached worktrees
#   git-prune-orphans -y/--yes         — skip the confirmation prompt
#   git-prune-orphans --dry-run        — works with any mode
#
# `-r` enables remote cleanup; `-R`/`--remote` are accepted aliases. Remote prune
# runs before local so the local pass surfaces branches whose remote was just
# deleted. Both passes PREVIEW what they will destroy and confirm before doing it.
#
# `-f`/`--force` no longer forces anything into deletion. It used to override the
# open-PR and grace-window holds — i.e. it force-deleted branches with an OPEN PR.
# Under landed-proof there is nothing left for it to override: a branch is deleted
# because its work is PROVEN to be on origin, and no flag can turn "I cannot prove
# this landed" into "destroy it". It now drops only the AGE grace on detached
# worktrees, which have no branch ref to prove anything about. It has never been,
# and is not, a licence to discard live work: locked and dirty worktrees are
# untouchable under every flag.
git-prune-orphans() {
  local do_remote=0 dry_run=0 force=0 assume_yes=0
  for arg in "$@"; do
    case "$arg" in
      -r|-R|--remote|--all-remote) do_remote=1 ;;
      -f|--force) force=1 ;;
      -y|--yes)   assume_yes=1 ;;
      --dry-run) dry_run=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  local fwd_args=()
  (( dry_run ))   && fwd_args+=(--dry-run)
  (( force ))     && fwd_args+=(--force)
  (( assume_yes )) && fwd_args+=(--yes)

  (( do_remote )) && { _git_prune_remote_orphans "$dry_run" "$assume_yes" || return 1; }

  _git_prune_local_orphans "${fwd_args[@]}"
}

# Remote prune (helper for git-prune-orphans -r). Deletes origin/<b> only when its
# work is PROVEN landed on origin (_git_remote_landed_proof) AND origin/<b>'s last
# commit is older than GIT_PRUNE_REMOTE_MIN_AGE (default 6h). Unknown age or any
# unprovable state → held back. This deletes SHARED state that may be the only
# surviving copy, so it gets proof first and the age window on top.
_git_prune_remote_orphans() {
  local dry_run="$1" assume_yes="${2:-0}"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  # Fail closed: deleting a REMOTE ref destroys the copy of last resort. If origin
  # cannot be fetched or named, nothing is provable and nothing is deleted.
  local preflight default gh_ok min candidates
  preflight=$(_git_landed_preflight "git-prune-orphans -r") || return 1
  IFS=$'\t' read -r default gh_ok <<< "$preflight"
  min=$(_git_prune_remote_min_age)
  candidates=$(_git_remote_orphans | sort -u)

  if [[ -z "$candidates" ]]; then
    echo "No remote-orphan candidates (every origin branch has an open PR)."
    return 0
  fi

  # PROOF, then age. The old gate was "no open PR, and 6h old" — both are the
  # ABSENCE of a signal, and on the REMOTE that is the most dangerous place to
  # reason from absence: origin is the durable copy. Under the session-scoped
  # worktree convention (RVT-2913) work that must survive is pushed to origin
  # precisely BECAUSE it is safe there, and this function was deleting exactly
  # that population — a pushed, PR-less, >6h branch is the *canonical* rescue
  # branch. It would have destroyed the 20 fork-bomb rescue branches outright.
  #
  # Now: delete origin/<b> only when its work is PROVEN landed. The 6h window is
  # kept as a second, subordinate hold — proof is necessary, age is not sufficient.
  local eligible="" held="" branch age verdict
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue

    verdict=$(_git_remote_landed_proof "$branch" "$default" "$gh_ok")
    if [[ "$verdict" != "landed" ]]; then
      held+="  origin/$branch  (${verdict#keep|})"$'\n'
      continue
    fi

    age=$(_git_ref_age_secs "refs/remotes/origin/$branch")
    if [[ -n "$age" ]] && (( age >= min )); then
      eligible+="$branch"$'\n'
    else
      held+="  origin/$branch  ($( [[ -n "$age" ]] && echo "$((age / 60))m < $((min / 60))m grace" || echo "age unknown — fail closed" ))"$'\n'
    fi
  done <<< "$candidates"

  [[ -n "$held" ]] && { echo "Held back (not proven landed, or within grace):"; printf '%s' "$held"; }

  eligible=$(printf '%s' "$eligible" | awk 'NF')
  if [[ -z "$eligible" ]]; then
    echo "No remote branches past the grace window."
    return 0
  fi

  local count
  count=$(printf '%s\n' "$eligible" | wc -l | tr -d ' ')

  # THE LIST SHOWN IS THE LIST DELETED — and this one deletes shared state, so it
  # is shown and confirmed even when the local pass would not bother.
  echo "Will DELETE $count remote branch(es) on origin (proven landed, past ${min}s grace):"
  printf '%s\n' "$eligible" | sed 's/^/  /'

  if (( dry_run )); then
    echo "--dry-run: nothing deleted."
    return 0
  fi

  if (( ! assume_yes )); then
    local reply
    read -q "reply?Delete these $count REMOTE branch(es) on origin? [y/N] "
    echo
    if [[ "$reply" != [yY] ]]; then
      echo "Aborted. Nothing deleted."
      return 0
    fi
  fi

  local deleted=0 failed=0
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    echo "Deleting origin/$branch"
    if git push origin --delete "$branch" 2>/dev/null; then
      deleted=$((deleted + 1))
    else
      echo "  failed to delete origin/$branch" >&2
      failed=$((failed + 1))
    fi
  done <<< "$eligible"

  echo "==> Deleted $deleted remote branch(es)$( (( failed > 0 )) && echo "; $failed failed" )."
}

# Local-only cleanup. Three categories of candidate:
#   1. Local branches with no corresponding branch on origin (_git_local_orphans)
#   2. Local branches checked out in a secondary worktree (regardless of remote
#      state — so claude worktrees that were pushed to origin still get cleaned
#      locally; the remote branch stays until you run the remote prune)
#   3. Secondary worktrees with detached HEAD (no branch ref at all — typical of
#      claude agent worktrees that died mid-flight; invisible to `git branch`
#      and to remote-branch checks, so categories 1 and 2 miss them)
#
# Each candidate is gated by the deletion policy (see § header):
#   - branch-keyed (1 & 2): DELETED ONLY ON POSITIVE PROOF OF LANDING
#     (_git_branch_landed_proof — merged into origin/<default>, or a MERGED PR on
#     origin). Anything unproven, INCLUDING every error path, is kept. Age plays no
#     part: a branch that is 2h old and unlanded is unlanded.
#   - detached worktrees (3): no branch ref exists, so landing cannot be proved or
#     disproved. These stay age-gated — the one place a grace window is honest —
#     and a dirty or locked one is never touched at any age.
# The main worktree's current checkout is treated as a non-worktree case.
#
# This function NEVER pushes to origin. For remote cleanup use `git-prune-orphans -r`.
#
# Usage:
#   _git_prune_local_orphans            — preview, then confirm before deleting
#   _git_prune_local_orphans --dry-run  — print the plan (delete vs protected) and exit
#   _git_prune_local_orphans --yes      — skip the confirmation prompt
#   _git_prune_local_orphans --force    — drop the AGE grace on detached worktrees only.
#                                         It can NOT force an unlanded branch to be
#                                         deleted, and never unlocks a worktree.
_git_prune_local_orphans() {
  local dry_run=0 _force=0 assume_yes=0
  for arg in "$@"; do
    case "$arg" in
      --dry-run)  dry_run=1 ;;
      --yes|-y)   assume_yes=1 ;;
      --force|-f) _force=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  # Fail closed: if origin cannot be fetched or its default branch named, nothing
  # can be PROVEN landed, so nothing may be deleted. The old code ran
  # `git fetch --prune ... || true` and then deleted on a stale/absent view.
  local preflight default gh_ok min
  preflight=$(_git_landed_preflight git-prune-orphans) || return 1
  IFS=$'\t' read -r default gh_ok <<< "$preflight"
  min=$(_git_prune_min_age)

  # Candidates: union of (local branches with no remote) and (branches checked
  # out in any secondary worktree, even if they have a remote tracker).
  local wt_info main_wt
  wt_info=$(git worktree list --porcelain)
  main_wt=$(echo "$wt_info" | awk '/^worktree / { print $2; exit }')

  local local_orphans secondary_wt_branches detached_wt
  local_orphans=$(_git_local_orphans)
  secondary_wt_branches=$(echo "$wt_info" | awk -v main="$main_wt" '
    BEGIN { RS = ""; FS = "\n" }
    {
      path = ""; br = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^worktree /) path = substr($i, 10)
        else if ($i ~ /^branch refs\/heads\//) br = substr($i, 19)
      }
      if (br != "" && path != main) print br
    }')

  # Detached-HEAD secondary worktrees — emit "<path>\t<locked>\t<head-sha>" so we
  # can age-gate them. These have no branch ref, so they are invisible to the
  # branch-keyed pass below.
  detached_wt=$(echo "$wt_info" | awk -v main="$main_wt" '
    BEGIN { RS = ""; FS = "\n" }
    {
      path = ""; has_branch = 0; lk = 0; hd = ""
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^worktree /) path = substr($i, 10)
        else if ($i ~ /^branch /) has_branch = 1
        else if ($i ~ /^HEAD /) hd = substr($i, 6)
        else if ($i ~ /^locked/) lk = 1
      }
      if (path != "" && path != main && !has_branch) print path "\t" lk "\t" hd
    }')

  local branches
  branches=$(printf '%s\n%s\n' "$local_orphans" "$secondary_wt_branches" \
             | awk 'NF && !seen[$0]++')

  if [[ -z "$branches" && -z "$detached_wt" ]]; then
    echo "No orphan branches or detached worktrees."
    return 0
  fi

  # Lookup: for a given branch name, emit "<path> <locked>" if it lives in a
  # secondary worktree, else emit nothing.
  _git_wt_lookup() {
    local b="$1"
    echo "$wt_info" | awk -v b="refs/heads/$b" -v main="$main_wt" '
      BEGIN { RS = ""; FS = "\n" }
      {
        path = ""; br = ""; lk = 0
        for (i = 1; i <= NF; i++) {
          if ($i ~ /^worktree /) path = substr($i, 10)
          else if ($i ~ /^branch /) br = substr($i, 8)
          else if ($i ~ /^locked/) lk = 1
        }
        if (br == b && path != main) { print path, lk; exit }
      }'
  }

  # Classify. del_branches: "<branch>\t<reason>"; protect_list: display lines.
  local del_branches="" del_detached="" protect_list=""
  # NB: _wt/_lk declared here, NOT inside the loop — a bare `local x` on an
  # already-set var re-prints "x=value" in zsh (a display op), leaking to stdout.
  local branch verdict _wt _lk
  if [[ -n "$branches" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue

      # PROOF FIRST. Not proven landed → kept, whatever its age, PR state, or
      # worktree status. --force cannot override this; there is no flag that
      # turns "I cannot prove this landed" into "destroy it".
      verdict=$(_git_branch_landed_proof "$branch" "$default" "$gh_ok")
      if [[ "$verdict" != "landed" ]]; then
        protect_list+="  $branch  (${verdict#keep|})"$'\n'
        continue
      fi

      # Landed, but still checked out in a live worktree: the BRANCH is safe to
      # delete, the DIRECTORY is not. A locked or dirty worktree is an agent
      # saying "this is mine and I am using it" — skip both. --force does not
      # relax this; it never did discard dirty/locked work, and now it cannot
      # relax the age hold into one either.
      read -r _wt _lk < <(_git_wt_lookup "$branch")
      if [[ -n "$_wt" ]] && _git_worktree_is_live "$_wt" "$_lk" $(( _force ? 0 : 1 )); then
        protect_list+="  $branch  (live worktree: $_wt)"$'\n'
        continue
      fi

      del_branches+="$branch"$'\t'"proven landed on origin"$'\n'
    done <<< "$branches"
  fi

  if [[ -n "$detached_wt" ]]; then
    local dpath dlk dhead dage
    while IFS=$'\t' read -r dpath dlk dhead; do
      [[ -z "$dpath" ]] && continue
      # Dirty/locked detached worktree → live agent; protect regardless of force
      # (age gate below guards young-but-clean ones; --force overrides that gate).
      if _git_worktree_is_live "$dpath" "$dlk" 0; then
        protect_list+="  $dpath  (live detached worktree: dirty or locked)"$'\n'
        continue
      fi
      dage=$(_git_ref_age_secs "$dhead")
      # An UNKNOWN age is not an old age. The old test read empty (= the age lookup
      # FAILED) as eligible-for-deletion, so an unreadable worktree was reaped
      # precisely because it could not be inspected. Unknown → keep.
      if [[ -z "$dage" ]]; then
        protect_list+="  $dpath  (detached worktree, age unresolvable — fail closed)"$'\n'
      elif (( _force )) || (( dage >= min )); then
        del_detached+="$dpath"$'\t'"$dlk"$'\n'
      else
        protect_list+="  $dpath  (detached worktree, $((dage / 60))m < $((min / 60))m grace)"$'\n'
      fi
    done <<< "$detached_wt"
  fi

  if [[ -n "$protect_list" ]]; then
    echo "Protected (kept):"
    printf '%s' "$protect_list"
  fi

  if [[ -z "$del_branches" && -z "$del_detached" ]]; then
    echo "Nothing eligible to delete."
    unset -f _git_wt_lookup
    return 0
  fi

  if (( dry_run )); then
    echo "Dry run: would delete:"
    [[ -n "$del_branches" ]] && printf '%s' "$del_branches" \
      | awk -F'\t' 'NF { print "  branch " $1 "  (" $2 ")" }'
    [[ -n "$del_detached" ]] && printf '%s' "$del_detached" \
      | awk -F'\t' 'NF { print "  detached worktree " $1 }'
    unset -f _git_wt_lookup
    return 0
  fi

  # THE LIST SHOWN IS THE LIST DELETED. Printed before anything is destroyed, and
  # the loops below iterate exactly these two lists. The old code showed only what
  # it PROTECTED and never showed what it was about to destroy — it just narrated
  # each deletion as it happened, which is a receipt, not a preview.
  echo "Will DELETE:"
  [[ -n "$del_branches" ]] && printf '%s' "$del_branches" \
    | awk -F'\t' 'NF { print "  branch " $1 "  (" $2 ")" }'
  [[ -n "$del_detached" ]] && printf '%s' "$del_detached" \
    | awk -F'\t' 'NF { print "  detached worktree " $1 }'

  if (( ! assume_yes )); then
    local reply
    read -q "reply?Proceed? [y/N] "
    echo
    if [[ "$reply" != [yY] ]]; then
      echo "Aborted. Nothing deleted."
      unset -f _git_wt_lookup
      return 0
    fi
  fi

  # wt_path/locked hoisted out of the loop — a bare in-loop `local` re-prints
  # "name=value" to stdout in zsh once the var is set (see classify loop above).
  local deleted=0 failed=0 wt_removed=0 wt_failed=0 reason wt_path locked
  if [[ -n "$del_branches" ]]; then
    while IFS=$'\t' read -r branch reason; do
      [[ -z "$branch" ]] && continue
      read -r wt_path locked < <(_git_wt_lookup "$branch")
      if [[ -n "$wt_path" ]]; then
        # A LOCK IS A VETO, NOT A FORMALITY. The old code unlocked the worktree and
        # then force-removed it — defeating the one mechanism an agent has to say
        # "do not touch this". That is the pattern that destroyed 22 worktrees on
        # 2026-07-13 (RVT-2881). There is no `git worktree unlock` in this file any
        # more. Locked → report and skip, including the branch.
        if [[ "$locked" == "1" ]]; then
          echo "  SKIP     $branch — worktree is LOCKED: $wt_path" >&2
          echo "           (a lock means an agent is using it; unlock it yourself if you disagree)" >&2
          failed=$((failed + 1))
          continue
        fi
        # No --force: git's own refusal to remove a dirty worktree is a real second
        # net, and `--force` existed only to defeat it. No `|| true`: the failure of
        # a destructive command is signal. If the worktree will not come out, we do
        # NOT go on to delete the branch it is holding.
        echo "  removing worktree $wt_path"
        if ! git worktree remove "$wt_path"; then
          echo "  SKIP     $branch — could not remove its worktree $wt_path" >&2
          echo "           (uncommitted work, or the directory is busy — nothing was deleted)" >&2
          wt_failed=$((wt_failed + 1))
          failed=$((failed + 1))
          continue
        fi
        wt_removed=$((wt_removed + 1))
      fi

      # -D, not -d, and ONLY because landing was already PROVEN above. A squash-
      # merged branch's commits are not ancestors of master, so `-d` would refuse it
      # and the tool would never clean anything. The force is safe here for exactly
      # one reason: the proof, not the flag.
      if git branch -D "$branch" 2>/dev/null; then
        echo "  deleted  $branch ($reason)"
        deleted=$((deleted + 1))
      else
        echo "  FAILED   $branch (still checked out somewhere, or the ref is locked)" >&2
        failed=$((failed + 1))
      fi
    done <<< "$del_branches"
  fi

  if [[ -n "$del_detached" ]]; then
    local dpath dlk
    while IFS=$'\t' read -r dpath dlk; do
      [[ -z "$dpath" ]] && continue
      if [[ "$dlk" == "1" ]]; then
        echo "  SKIP     detached worktree is LOCKED: $dpath" >&2
        wt_failed=$((wt_failed + 1))
        continue
      fi
      if git worktree remove "$dpath"; then
        echo "  removed  detached worktree $dpath"
        wt_removed=$((wt_removed + 1))
      else
        echo "  FAILED   could not remove detached worktree $dpath (uncommitted work?)" >&2
        wt_failed=$((wt_failed + 1))
      fi
    done <<< "$del_detached"
  fi

  unset -f _git_wt_lookup
  echo "==> Deleted $deleted branch(es)$( (( failed > 0 )) && echo "; $failed skipped/failed" ); removed $wt_removed worktree(s)$( (( wt_failed > 0 )) && echo "; $wt_failed skipped/failed" )."
}

# Batch-merge every open PR: folded into `git-merge-pr-clean --all` (squash-admin
# per PR via the scoped engine, then -l/-r/-R orphan sweep). See that function.

# One-shot repo sync + cleanup — the daily-driver combo. Fast-forward pulls the
# current branch, refreshes tags, then prunes local branches PROVEN landed on origin.
# Safe in shared repos: the default never deletes anything on origin.
# Aliased to `gsp` (see aliases.zsh) so it's a 3-keystroke, tab-free invocation.
#
# THIS IS THE MOST DANGEROUS ENTRY POINT IN THIS FILE, because it is the one you type
# without thinking. Until RVT-2886 it reached a pruner that force-deleted any branch
# with no PR whose last commit was >2h old — no preview, no confirmation. A never-
# pushed WIP branch two hours old was destroyed by a command whose name is "sync".
# It now deletes a branch only on POSITIVE PROOF the work is on origin, and shows you
# the list and asks before it does. See the "Orphan pruning" § header.
#
#   git-sync            — pull --ff-only (if upstream) + fetch --tags --prune + local prune
#   git-sync -r         — also run the remote prune (proven-landed, 6h-gated)
#   git-sync -f         — drop the AGE grace on detached worktrees. It can NOT force an
#                         unlanded branch to be deleted (locked/dirty worktrees, and
#                         anything unproven, stay protected under every flag).
#   git-sync -y         — skip the confirmation prompt
#   git-sync --dry-run  — still syncs, then previews the prune without deleting
#
# Grace windows: GIT_PRUNE_MIN_AGE (detached worktrees, default 7200s = 2h) and
# GIT_PRUNE_REMOTE_MIN_AGE (remote, default 21600s = 6h).
git-sync() {
  local dry_run=0 remote=0 force=0 assume_yes=0 arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run)               dry_run=1 ;;
      -r|-R|--remote)          remote=1 ;;
      -f|--force)              force=1 ;;
      -y|--yes)                assume_yes=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "Error: not in a git repo" >&2; return 1; }

  local upstream
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)
  if [[ -n "$upstream" ]]; then
    echo "==> Fast-forward pull ($upstream)"
    git pull --ff-only || return 1
  else
    echo "==> No upstream for current branch; skipping pull"
  fi

  echo "==> Fetching tags"
  git fetch --tags --prune || true

  local -a prune_args=()
  (( remote ))     && prune_args+=(-r)
  (( force ))      && prune_args+=(-f)
  (( assume_yes )) && prune_args+=(-y)
  (( dry_run ))    && prune_args+=(--dry-run)
  echo "==> Pruning orphans"
  git-prune-orphans "${prune_args[@]}"
}
