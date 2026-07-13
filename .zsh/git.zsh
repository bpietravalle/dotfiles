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

  # Fail closed: without a fresh view of origin we cannot prove anything landed.
  if ! git fetch --prune; then
    echo "git-prune-gone: 'git fetch --prune' FAILED — refusing to delete anything." >&2
    echo "  (cannot prove what landed without a current view of origin; fail closed)" >&2
    return 1
  fi

  # Fail closed: the default branch is the ancestor test's reference point.
  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  if [[ -z "$default" ]] || ! git rev-parse --verify --quiet "refs/remotes/origin/$default" >/dev/null; then
    echo "git-prune-gone: cannot resolve origin's default branch — refusing to delete anything." >&2
    echo "  (try: git remote set-head origin -a)" >&2
    return 1
  fi

  # gh proves the squash-merge case. Without it we can still prove ordinary merges via
  # the ancestor test; squash-merged branches simply stay KEPT (fail closed, not silent).
  local gh_ok=0
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh_ok=1
  fi

  local -a landed keep_reasons
  local branch rc pr

  while IFS= read -r branch; do
    [[ -n "$branch" ]] || continue
    [[ "$branch" == "$default" ]] && continue

    # PROOF 1 — ordinary merge: the tip is reachable from origin/<default>.
    # Exit codes: 0 = ancestor, 1 = not an ancestor, anything else = ERROR. An error
    # must never be read as "not landed AND therefore fine to look at further"; it is
    # simply not proof, so the branch is kept either way.
    git merge-base --is-ancestor "refs/heads/$branch" "refs/remotes/origin/$default" 2>/dev/null
    rc=$?
    if (( rc == 0 )); then
      landed+=("$branch")
      continue
    elif (( rc != 1 )); then
      keep_reasons+=("$branch|KEPT: error resolving ancestry (git exit $rc) — fail closed")
      continue
    fi

    # PROOF 2 — squash merge: origin has a MERGED PR whose head is this branch.
    if (( gh_ok )); then
      pr=$(gh pr list --head "$branch" --state merged --limit 1 --json number \
             --jq '.[0].number' 2>/dev/null)
      rc=$?
      if (( rc != 0 )); then
        keep_reasons+=("$branch|KEPT: could not query origin for a merged PR — fail closed")
      elif [[ -n "$pr" && "$pr" != "null" ]]; then
        landed+=("$branch")
      else
        keep_reasons+=("$branch|KEPT: not merged into origin/$default and no merged PR — unlanded work")
      fi
    else
      keep_reasons+=("$branch|KEPT: gh unavailable/unauthenticated, cannot prove a squash-merged PR — fail closed")
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
  local branch wt_path locked deleted=0 wt_removed=0 failed=0
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
      if [[ "$locked" == "1" ]]; then
        echo "Unlocking worktree: $wt_path"
        git worktree unlock "$wt_path" 2>/dev/null || true
      fi
      echo "Removing worktree: $wt_path"
      if git worktree remove --force "$wt_path" 2>/dev/null; then
        wt_removed=$((wt_removed + 1))
      else
        echo "  failed to remove $wt_path" >&2
        failed=$((failed + 1))
      fi
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
# Deletion policy — LOCAL and REMOTE are independent time gates (no coupling):
#   1. Captured work is always deletable — a branch whose commits are merged into
#      the default branch, or whose head branch has a closed/merged PR.
#   2. A branch/remote with an OPEN PR is PROTECTED (you may still push fixes).
#   3. LOCAL: an uncaptured branch (no PR, not merged) or a detached worktree is
#      eligible once its last commit is older than GIT_PRUNE_MIN_AGE seconds
#      (default 7200 = 2h). Shields active local WIP / live agent worktrees.
#   4. REMOTE (`-r`): any origin branch with no open PR is eligible once its last
#      commit is older than GIT_PRUNE_REMOTE_MIN_AGE seconds (default 21600 = 6h).
#      NOT coupled to local — a remote-only branch is fair game after 6h. The
#      longer window is the safety margin for the shared remote (an engineer's
#      untouched-for-6h, PR-less branch is treated as abandoned).
#
#   git-prune-orphans          — UNIFIED entry point. Default = local only.
#                                -r → remote (all no-PR origin branches, 6h-gated)
#                                     THEN local. Remote-enable is a single flag.
#   _git_remote_orphans         — LIST remote branches on origin with no open PR
#   _git_prune_remote_orphans   — DELETE no-PR, 6h-aged remote branches
#   _git_local_orphans          — LIST local branches with no corresponding remote
#   _git_prune_local_orphans    — DELETE captured/aged-out local orphans AND the
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

# The ref against which "captured" (merged) is judged: prefer origin/<default>,
# else the local <default>. Empty if neither exists.
_git_capture_ref() {
  local default="$1"
  if git rev-parse --verify --quiet "refs/remotes/origin/$default" >/dev/null; then
    echo "refs/remotes/origin/$default"
  elif git rev-parse --verify --quiet "refs/heads/$default" >/dev/null; then
    echo "refs/heads/$default"
  fi
}

# Grace window (seconds) before an uncaptured LOCAL branch/worktree is prunable.
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
  [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]] && return 0
  if (( check_age )); then
    local ct min
    ct=$(git -C "$wt" log -1 --format=%ct HEAD 2>/dev/null)
    if [[ -n "$ct" ]]; then
      min=$(_git_prune_min_age)
      (( $(date +%s) - ct < min )) && return 0
    fi
  fi
  return 1
}

# Emit "<STATE>\t<headRefName>" for every PR (all states). One gh call; the
# result is cached by callers and passed to _git_branch_prune_verdict. Empty if
# gh is unavailable — callers then treat every branch as PR-less (age-gated),
# which errs toward protecting young work rather than deleting it.
_git_pr_branch_states() {
  gh pr list --state all --limit 500 --json state,headRefName \
    -q '.[] | .state + "\t" + .headRefName' 2>/dev/null
}

# Classify a local branch for pruning. Echoes exactly one verdict:
#   deletable-captured — merged into default, or head branch has a closed/merged PR
#   protect-open       — head branch has an OPEN PR (keep)
#   deletable-old      — uncaptured, last commit past the grace window
#   protect-young      — uncaptured, last commit within the grace window (keep)
# Args: <branch> <pr-state-cache> <default-branch>
_git_branch_prune_verdict() {
  local branch="$1" pr_cache="$2" default="$3"

  local cap_ref
  cap_ref=$(_git_capture_ref "$default")
  if [[ -n "$cap_ref" ]] \
     && git merge-base --is-ancestor "refs/heads/$branch" "$cap_ref" 2>/dev/null; then
    printf 'deletable-captured'; return 0
  fi

  local state
  state=$(printf '%s\n' "$pr_cache" | awk -F'\t' -v b="$branch" '$2 == b {print $1; exit}')
  if [[ -n "$state" ]]; then
    [[ "$state" == "OPEN" ]] && { printf 'protect-open'; return 0; }
    printf 'deletable-captured'; return 0
  fi

  local age min
  age=$(_git_ref_age_secs "refs/heads/$branch")
  min=$(_git_prune_min_age)
  if [[ -z "$age" ]] || (( age >= min )); then
    printf 'deletable-old'
  else
    printf 'protect-young'
  fi
  return 0
}

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
#   git-prune-orphans -r               — remote (all no-PR origin branches, 6h-gated), then local
#   git-prune-orphans -f               — force LOCAL prune: also delete branches with an
#                                        open PR or still within the grace window
#   git-prune-orphans --dry-run        — works with any mode
#
# `-r` enables remote cleanup; `-R`/`--remote` are accepted aliases (there is a
# single remote mode now). No confirmation prompts. Remote prune runs before
# local so the local pass surfaces branches whose remote was just deleted.
#
# `-f`/`--force` overrides the open-PR and grace-window holds for the LOCAL prune
# only (so you can reap a branch whose PR is already up). It still refuses to
# force-remove a worktree with uncommitted work or an explicit lock — force is
# not a licence to discard live work. Remote deletion stays PR-/age-gated.
git-prune-orphans() {
  local do_remote=0 dry_run=0 force=0
  for arg in "$@"; do
    case "$arg" in
      -r|-R|--remote|--all-remote) do_remote=1 ;;
      -f|--force) force=1 ;;
      --dry-run) dry_run=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  local fwd_args=()
  (( dry_run )) && fwd_args+=(--dry-run)
  (( force ))   && fwd_args+=(--force)

  (( do_remote )) && { _git_prune_remote_orphans "$dry_run" || return 1; }

  _git_prune_local_orphans "${fwd_args[@]}"
}

# Remote prune (helper for git-prune-orphans -r). Deletes origin/<b> when BOTH:
#   - <b> has no open PR (a remote orphan, per _git_remote_orphans)
#   - origin/<b>'s last commit is older than GIT_PRUNE_REMOTE_MIN_AGE (default 6h)
# NOT coupled to local branches — a remote-only branch is fair game once past the
# 6h window. Unknown remote age → held back (fail-safe: never delete shared state
# we can't date). Snapshot is taken before any mutation.
_git_prune_remote_orphans() {
  local dry_run="$1"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  git fetch --prune >/dev/null 2>&1 || true

  local min candidates
  min=$(_git_prune_remote_min_age)
  candidates=$(_git_remote_orphans | sort -u)

  if [[ -z "$candidates" ]]; then
    echo "No remote-orphan candidates (every origin branch has an open PR)."
    return 0
  fi

  # Age-gate each candidate on its remote ref's last commit.
  local eligible="" held="" branch age
  while IFS= read -r branch; do
    [[ -z "$branch" ]] && continue
    age=$(_git_ref_age_secs "refs/remotes/origin/$branch")
    if [[ -n "$age" ]] && (( age >= min )); then
      eligible+="$branch"$'\n'
    else
      held+="  origin/$branch  ($( [[ -n "$age" ]] && echo "$((age / 60))m < $((min / 60))m grace" || echo "age unknown" ))"$'\n'
    fi
  done <<< "$candidates"

  [[ -n "$held" ]] && { echo "Held back (within grace window):"; printf '%s' "$held"; }

  eligible=$(printf '%s' "$eligible" | awk 'NF')
  if [[ -z "$eligible" ]]; then
    echo "No remote branches past the grace window."
    return 0
  fi

  local count
  count=$(printf '%s\n' "$eligible" | wc -l | tr -d ' ')

  if (( dry_run )); then
    echo "Dry run: would delete $count remote branch(es) on origin (no open PR, past ${min}s grace):"
    printf '%s\n' "$eligible" | sed 's/^/  /'
    return 0
  fi

  echo "Deleting $count remote branch(es) on origin (no open PR, past ${min}s grace):"

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
#   - branch-keyed (1 & 2): _git_branch_prune_verdict decides. Captured (merged
#     or closed/merged PR) → delete; OPEN PR → protect; uncaptured → delete only
#     past the grace window, else protect. On delete, remove its worktree first.
#   - detached worktrees (3): age-gated on the worktree HEAD — removed only past
#     the grace window (protects a live agent worktree that just died).
# The main worktree's current checkout is treated as a non-worktree case.
#
# This function NEVER pushes to origin. For remote cleanup use `git-prune-orphans
# -r` (no-PR origin branches, 6h-gated).
#
# Usage:
#   _git_prune_local_orphans            — delete (no confirmation; runs immediately)
#   _git_prune_local_orphans --dry-run  — print the plan (delete vs protected) and exit
#   _git_prune_local_orphans --force    — also reap open-PR / within-grace branches
#                                         (still protects dirty/locked worktrees)
_git_prune_local_orphans() {
  local dry_run=0 _force=0
  for arg in "$@"; do
    case "$arg" in
      --dry-run)  dry_run=1 ;;
      --force|-f) _force=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  git fetch --prune >/dev/null 2>&1 || true

  local default pr_cache min
  default=$(_git_default_branch)
  pr_cache=$(_git_pr_branch_states)
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
  local branch verdict age _wt _lk
  if [[ -n "$branches" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      verdict=$(_git_branch_prune_verdict "$branch" "$pr_cache" "$default")
      # --force overrides the PR-open and grace-window holds (but never the
      # dirty/locked worktree guard below).
      if (( _force )); then
        case "$verdict" in
          protect-open)  verdict=deletable-captured ;;
          protect-young) verdict=deletable-old ;;
        esac
      fi
      case "$verdict" in
        deletable-captured|deletable-old)
          # Live-worktree guard: never reap a branch checked out in an active
          # secondary worktree (locked / dirty / young HEAD) — even when its PR
          # merged (captured, which otherwise skips the grace window). This is
          # the fix for concurrent git-sync wiping a still-running agent. Under
          # --force the young-HEAD hold is dropped (check_age=0), but dirty and
          # locked worktrees stay protected — force never discards live work.
          read -r _wt _lk < <(_git_wt_lookup "$branch")
          if [[ -n "$_wt" ]] && _git_worktree_is_live "$_wt" "$_lk" $(( _force ? 0 : 1 )); then
            protect_list+="  $branch  (live worktree: $_wt)"$'\n'
          elif [[ "$verdict" == "deletable-captured" ]]; then
            del_branches+="$branch"$'\t'"captured"$'\n'
          else
            del_branches+="$branch"$'\t'"uncaptured, past grace"$'\n'
          fi
          ;;
        protect-open)       protect_list+="  $branch  (open PR)"$'\n' ;;
        protect-young)
          age=$(_git_ref_age_secs "refs/heads/$branch")
          protect_list+="  $branch  (unpushed WIP, $((age / 60))m < $((min / 60))m grace)"$'\n' ;;
      esac
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
      if (( _force )) || [[ -z "$dage" ]] || (( dage >= min )); then
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

  # wt_path/locked hoisted out of the loop — a bare in-loop `local` re-prints
  # "name=value" to stdout in zsh once the var is set (see classify loop above).
  local deleted=0 failed=0 wt_removed=0 wt_failed=0 reason wt_path locked
  if [[ -n "$del_branches" ]]; then
    while IFS=$'\t' read -r branch reason; do
      [[ -z "$branch" ]] && continue
      read -r wt_path locked < <(_git_wt_lookup "$branch")
      if [[ -n "$wt_path" ]]; then
        if [[ "$locked" == "1" ]]; then
          echo "Unlocking worktree: $wt_path"
          git worktree unlock "$wt_path" || true
        fi
        echo "Removing worktree: $wt_path"
        git worktree remove --force "$wt_path" || true
      fi
      echo "Deleting branch: $branch ($reason)"
      if git branch -D "$branch" 2>/dev/null; then
        deleted=$((deleted + 1))
      else
        echo "  failed (likely current branch in some worktree)" >&2
        failed=$((failed + 1))
      fi
    done <<< "$del_branches"
  fi

  if [[ -n "$del_detached" ]]; then
    local dpath dlk
    while IFS=$'\t' read -r dpath dlk; do
      [[ -z "$dpath" ]] && continue
      if [[ "$dlk" == "1" ]]; then
        echo "Unlocking worktree: $dpath"
        git worktree unlock "$dpath" || true
      fi
      echo "Removing detached worktree: $dpath"
      if git worktree remove --force "$dpath" 2>/dev/null; then
        wt_removed=$((wt_removed + 1))
      else
        echo "  failed to remove $dpath" >&2
        wt_failed=$((wt_failed + 1))
      fi
    done <<< "$del_detached"
  fi

  unset -f _git_wt_lookup
  echo "==> Deleted $deleted branch(es)$( (( failed > 0 )) && echo "; $failed failed" ); removed $wt_removed detached worktree(s)$( (( wt_failed > 0 )) && echo "; $wt_failed failed" )."
}

# Batch-merge every open PR: folded into `git-merge-pr-clean --all` (squash-admin
# per PR via the scoped engine, then -l/-r/-R orphan sweep). See that function.

# One-shot repo sync + cleanup — the daily-driver combo. Fast-forward pulls the
# current branch, refreshes tags, then prunes captured/aged-out local orphans.
# Safe in shared repos: the default never deletes anything on origin.
# Aliased to `gsp` (see aliases.zsh) so it's a 3-keystroke, tab-free invocation.
#
#   git-sync            — pull --ff-only (if upstream) + fetch --tags --prune + local prune
#   git-sync -r         — also run the remote prune (no-PR origin branches, 6h-gated)
#   git-sync -f         — force the local prune: reap branches with an open PR or
#                         still within grace (dirty/locked worktrees stay protected)
#   git-sync --dry-run  — still syncs, then previews the prune without deleting
#
# Grace windows: GIT_PRUNE_MIN_AGE (local, default 7200s = 2h) and
# GIT_PRUNE_REMOTE_MIN_AGE (remote, default 21600s = 6h); see the "Orphan
# pruning" § header.
git-sync() {
  local dry_run=0 remote=0 force=0 arg
  for arg in "$@"; do
    case "$arg" in
      --dry-run)               dry_run=1 ;;
      -r|-R|--remote)          remote=1 ;;
      -f|--force)              force=1 ;;
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
  (( remote ))  && prune_args+=(-r)
  (( force ))   && prune_args+=(-f)
  (( dry_run )) && prune_args+=(--dry-run)
  echo "==> Pruning orphans"
  git-prune-orphans "${prune_args[@]}"
}
