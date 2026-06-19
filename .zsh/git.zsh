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

# Delete local branches whose upstream tracking branch no longer exists on remote.
# Handy after squash-merged PRs where GitHub auto-deletes the head branch.
# Uses -D (force) since squash merges produce different SHAs than the local branch.
# Skips branches that are checked out in any worktree (Claude Code agent worktrees, etc).
# Best-effort: always returns 0 so callers can chain without bailing on partial cleanup.
git-prune-gone() {
  git fetch --prune || return 1

  local gone
  gone=$(git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads \
         | awk '$2 == "[gone]" {print $1}')

  if [[ -z "$gone" ]]; then
    echo "No gone branches."
    return 0
  fi

  # Branches currently checked out in any worktree — never try to delete these
  local worktree_branches
  worktree_branches=$(git worktree list --porcelain \
                      | awk '/^branch / {sub("refs/heads/", "", $2); print $2}')

  local skipped="" prunable="$gone"
  if [[ -n "$worktree_branches" ]]; then
    skipped=$(echo "$gone"  | grep -xFf <(echo "$worktree_branches") 2>/dev/null || true)
    prunable=$(echo "$gone" | grep -vxFf <(echo "$worktree_branches") 2>/dev/null || true)
  fi

  if [[ -n "$skipped" ]]; then
    echo "Skipped (in use by worktree):"
    echo "$skipped" | sed 's/^/  /'
  fi

  if [[ -z "$prunable" ]]; then
    return 0
  fi

  # If current branch is among the prunable ones, switch off it first
  local current default
  current=$(git symbolic-ref --short HEAD 2>/dev/null)
  if echo "$prunable" | grep -qx "$current"; then
    default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    : "${default:=master}"
    echo "Switching off '$current' to '$default' before deletion..."
    git switch "$default" || return 1
  fi

  echo "$prunable" | xargs git branch -D || true
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
#   -r   also run `git-prune-orphans -r` (SAFE remote + local)
#   -R   also run `git-prune-orphans -R` (AGGRESSIVE remote + local — affects everyone)
# -r and -R are mutually exclusive; -l is implied by either.
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
      -l)        prune_local=1; shift ;;
      -r)
        [[ "$prune_remote_mode" == "all" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        prune_remote_mode="safe"; shift ;;
      -R)
        [[ "$prune_remote_mode" == "safe" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        prune_remote_mode="all"; shift ;;
      -lr|-rl)
        [[ "$prune_remote_mode" == "all" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        prune_local=1; prune_remote_mode="safe"; shift ;;
      -lR|-Rl)
        [[ "$prune_remote_mode" == "safe" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        prune_local=1; prune_remote_mode="all"; shift ;;
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
      safe) git-prune-orphans -r --dry-run ;;
      all)  git-prune-orphans -R --dry-run ;;
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
    safe) git-prune-orphans -r ;;
    all)  git-prune-orphans -R ;;
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
        any_wt=1
        echo "  $branch  ($wt_path)$([[ "$locked" == "1" ]] && echo ' [locked]')"
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
# Unified entry point + four primitives. Default: local only (safe in shared
# repos — never touches origin, so other engineers' branches are preserved).
#
#   git-prune-orphans          — UNIFIED entry point. Default = local only.
#                                -r → SAFE remote (only delete origin/<b> where
#                                     <b> also exists locally) THEN local.
#                                -R → AGGRESSIVE remote (every remote branch with
#                                     no open PR, regardless of local) THEN local.
#                                Remote prune runs FIRST so subsequent local prune
#                                surfaces branches whose remote was just deleted.
#   _git_remote_orphans         — LIST remote branches on origin with no open PR
#   _git_prune_remote_orphans   — DELETE those remote branches (push --delete).
#                                Aggressive; same as `git-prune-orphans -R` minus
#                                the chained local prune. Affects everyone.
#   _git_local_orphans          — LIST local branches with no corresponding remote
#                                branch on origin
#   _git_prune_local_orphans    — DELETE local-orphan branches AND remove the
#                                worktrees that hold them. Also picks up branches
#                                checked out in any secondary worktree (so claude
#                                worktrees that were pushed to origin still get
#                                cleaned locally). Never touches origin.
#
# ─────────────────────────────────────────────────────────────────────────────

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

# Delete remote branches on origin that have no open PR (and aren't the default).
# Uses `git push origin --delete`. No confirmation — runs immediately.
#
# Usage:
#   _git_prune_remote_orphans            — delete
#   _git_prune_remote_orphans --dry-run  — print what would be deleted and exit
_git_prune_remote_orphans() {
  local dry_run=0
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  git fetch --prune >/dev/null 2>&1 || true

  local branches
  branches=$(_git_remote_orphans)

  if [[ -z "$branches" ]]; then
    echo "No remote orphan branches on origin."
    return 0
  fi

  local count
  count=$(echo "$branches" | wc -l | tr -d ' ')

  if (( dry_run )); then
    echo "Dry run: would delete $count remote branch(es) on origin:"
    echo "$branches" | sed 's/^/  /'
    return 0
  fi

  echo "Deleting $count remote branch(es) on origin (no open PR):"

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
  done <<< "$branches"

  echo "==> Deleted $deleted remote branch(es)$( (( failed > 0 )) && echo "; $failed failed" )."
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
#   git-prune-orphans -r               — SAFE remote (locally-present ∩ orphan), then local
#   git-prune-orphans -R               — AGGRESSIVE remote (all orphans), then local
#   git-prune-orphans --dry-run        — works with any mode
#
# No confirmation prompts — runs immediately. -r and -R are mutually exclusive.
# Remote prune always runs before local prune so the local pass surfaces branches
# whose remote was just deleted.
git-prune-orphans() {
  local mode_remote="" dry_run=0
  for arg in "$@"; do
    case "$arg" in
      -r)
        [[ -n "$mode_remote" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        mode_remote="safe" ;;
      -R|--all-remote)
        [[ -n "$mode_remote" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        mode_remote="all" ;;
      --dry-run) dry_run=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  local fwd_args=()
  (( dry_run )) && fwd_args+=(--dry-run)

  if [[ "$mode_remote" == "all" ]]; then
    _git_prune_remote_orphans "${fwd_args[@]}" || return 1
  elif [[ "$mode_remote" == "safe" ]]; then
    _git_prune_remote_safe "$dry_run" || return 1
  fi

  _git_prune_local_orphans "${fwd_args[@]}"
}

# Safe-mode remote prune (helper for git-prune-orphans -r). Deletes origin/<b>
# only when <b> also exists in the local branch list AND is in the remote-orphan
# set (no open PR). Snapshot is taken before any mutation, so branches that
# exist ONLY on origin (other engineers' work) are never touched.
_git_prune_remote_safe() {
  local dry_run="$1"

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  git fetch --prune >/dev/null 2>&1 || true

  local local_branches remote_orphans candidates
  local_branches=$(git for-each-ref --format='%(refname:short)' refs/heads | sort -u)
  remote_orphans=$(_git_remote_orphans | sort -u)
  candidates=$(comm -12 <(echo "$local_branches") <(echo "$remote_orphans"))

  if [[ -z "$candidates" ]]; then
    echo "No safe remote-orphan candidates (no local branches intersect the remote-orphan set)."
    return 0
  fi

  local count
  count=$(echo "$candidates" | wc -l | tr -d ' ')

  if (( dry_run )); then
    echo "Dry run: would delete $count remote branch(es) on origin (safe mode — locally present):"
    echo "$candidates" | sed 's/^/  /'
    return 0
  fi

  echo "Deleting $count remote branch(es) on origin (safe mode — locally present, no open PR):"

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
  done <<< "$candidates"

  echo "==> Deleted $deleted remote branch(es)$( (( failed > 0 )) && echo "; $failed failed" )."
}

# Local-only cleanup. Three categories of candidate:
#   1. Local branches with no corresponding branch on origin (_git_local_orphans)
#   2. Local branches checked out in a secondary worktree (regardless of remote
#      state — so claude worktrees that were pushed to origin still get cleaned
#      locally; the remote branch stays until you run _git_prune_remote_orphans)
#   3. Secondary worktrees with detached HEAD (no branch ref at all — typical of
#      claude agent worktrees that died mid-flight; invisible to `git branch`
#      and to remote-branch checks, so categories 1 and 2 miss them)
#
# For each candidate:
#   - categories 1 & 2 (branch-keyed): if checked out in a secondary worktree,
#     unlock if locked, remove the worktree, then delete the branch; otherwise
#     just delete the branch
#   - category 3 (path-keyed, no branch): unlock if locked, remove the worktree
# The main worktree's current checkout is treated as a non-worktree case.
#
# This function NEVER pushes to origin. If you want to clean up remote branches
# too, run _git_prune_remote_orphans separately.
#
# Usage:
#   _git_prune_local_orphans            — delete (no confirmation; runs immediately)
#   _git_prune_local_orphans --dry-run  — print counts (worktree vs non-worktree) and exit
_git_prune_local_orphans() {
  local dry_run=0
  for arg in "$@"; do
    case "$arg" in
      --dry-run) dry_run=1 ;;
      *) echo "Unknown arg: $arg" >&2; return 2 ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  git fetch --prune >/dev/null 2>&1 || true

  # Candidates: union of (local branches with no remote) and (branches checked
  # out in any secondary worktree, even if they have a remote tracker).
  local wt_info main_wt
  wt_info=$(git worktree list --porcelain)
  main_wt=$(echo "$wt_info" | awk '/^worktree / { print $2; exit }')

  local local_orphans secondary_wt_branches detached_wt_paths
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

  # Exclude open-PR branches from the secondary-worktree set — a branch held by
  # an agent worktree while its PR is open/under-review should not be reaped.
  # Best-effort; if `gh` is unavailable or fails we leave the set as-is.
  if [[ -n "$secondary_wt_branches" ]]; then
    local open_pr_branches
    open_pr_branches=$(gh pr list --state open --json headRefName -q '.[].headRefName' 2>/dev/null | sort -u)
    if [[ -n "$open_pr_branches" ]]; then
      secondary_wt_branches=$(comm -23 <(echo "$secondary_wt_branches" | sort -u) <(echo "$open_pr_branches"))
    fi
  fi

  # Detached-HEAD secondary worktrees — emit "<path>\t<locked>" so we can
  # iterate them without re-parsing later. These have no branch ref, so they
  # are invisible to the branch-keyed pass below.
  detached_wt_paths=$(echo "$wt_info" | awk -v main="$main_wt" '
    BEGIN { RS = ""; FS = "\n" }
    {
      path = ""; has_branch = 0; lk = 0
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^worktree /) path = substr($i, 10)
        else if ($i ~ /^branch /) has_branch = 1
        else if ($i ~ /^locked/) lk = 1
      }
      if (path != "" && path != main && !has_branch) print path "\t" lk
    }')

  local branches
  branches=$(printf '%s\n%s\n' "$local_orphans" "$secondary_wt_branches" \
             | awk 'NF && !seen[$0]++')

  if [[ -z "$branches" && -z "$detached_wt_paths" ]]; then
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

  local wt_count=0 nonwt_count=0 detached_count=0
  local wt_list="" nonwt_list="" detached_list=""
  if [[ -n "$branches" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      local wt_path locked
      read -r wt_path locked < <(_git_wt_lookup "$branch")
      if [[ -n "$wt_path" ]]; then
        wt_count=$((wt_count + 1))
        wt_list+="  $branch  ($wt_path)$([[ "$locked" == "1" ]] && echo ' [locked]')"$'\n'
      else
        nonwt_count=$((nonwt_count + 1))
        nonwt_list+="  $branch"$'\n'
      fi
    done <<< "$branches"
  fi

  if [[ -n "$detached_wt_paths" ]]; then
    while IFS=$'\t' read -r wt_path locked; do
      [[ -z "$wt_path" ]] && continue
      detached_count=$((detached_count + 1))
      detached_list+="  $wt_path$([[ "$locked" == "1" ]] && echo ' [locked]')"$'\n'
    done <<< "$detached_wt_paths"
  fi

  if (( dry_run )); then
    echo "Dry run: would delete $wt_count worktree branch(es), $nonwt_count non-worktree branch(es), $detached_count detached worktree(s)."
    [[ -n "$wt_list" ]]       && { echo "Worktree branches:";    printf '%s' "$wt_list"; }
    [[ -n "$nonwt_list" ]]    && { echo "Non-worktree branches:"; printf '%s' "$nonwt_list"; }
    [[ -n "$detached_list" ]] && { echo "Detached worktrees:";   printf '%s' "$detached_list"; }
    unset -f _git_wt_lookup
    return 0
  fi

  echo "Deleting $wt_count worktree branch(es), $nonwt_count non-worktree branch(es), and $detached_count detached worktree(s):"
  [[ -n "$wt_list" ]]       && { echo "Worktree branches:";    printf '%s' "$wt_list"; }
  [[ -n "$nonwt_list" ]]    && { echo "Non-worktree branches:"; printf '%s' "$nonwt_list"; }
  [[ -n "$detached_list" ]] && { echo "Detached worktrees:";   printf '%s' "$detached_list"; }

  local deleted=0 failed=0 wt_removed=0 wt_failed=0
  if [[ -n "$branches" ]]; then
    while IFS= read -r branch; do
      [[ -z "$branch" ]] && continue
      local wt_path locked
      read -r wt_path locked < <(_git_wt_lookup "$branch")
      if [[ -n "$wt_path" ]]; then
        if [[ "$locked" == "1" ]]; then
          echo "Unlocking worktree: $wt_path"
          git worktree unlock "$wt_path" || true
        fi
        echo "Removing worktree: $wt_path"
        git worktree remove --force "$wt_path" || true
      fi
      echo "Deleting branch: $branch"
      if git branch -D "$branch" 2>/dev/null; then
        deleted=$((deleted + 1))
      else
        echo "  failed (likely current branch in some worktree)" >&2
        failed=$((failed + 1))
      fi
    done <<< "$branches"
  fi

  if [[ -n "$detached_wt_paths" ]]; then
    while IFS=$'\t' read -r wt_path locked; do
      [[ -z "$wt_path" ]] && continue
      if [[ "$locked" == "1" ]]; then
        echo "Unlocking worktree: $wt_path"
        git worktree unlock "$wt_path" || true
      fi
      echo "Removing detached worktree: $wt_path"
      if git worktree remove --force "$wt_path" 2>/dev/null; then
        wt_removed=$((wt_removed + 1))
      else
        echo "  failed to remove $wt_path" >&2
        wt_failed=$((wt_failed + 1))
      fi
    done <<< "$detached_wt_paths"
  fi

  unset -f _git_wt_lookup
  echo "==> Deleted $deleted branch(es)$( (( failed > 0 )) && echo "; $failed failed" ); removed $wt_removed detached worktree(s)$( (( wt_failed > 0 )) && echo "; $wt_failed failed" )."
}

# Batch-merge every open PR: folded into `git-merge-pr-clean --all` (squash-admin
# per PR via the scoped engine, then -l/-r/-R orphan sweep). See that function.
