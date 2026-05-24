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

# Squash-merge a PR (admin override), sync the default branch, and prune gone
# branches. Two modes:
#   git-merge-pr-clean             — merge the PR for the current branch
#   git-merge-pr-clean <pr-number> — merge a specific PR (caller already on default)
#
# Optional cleanup flags (in addition to the always-on git-prune-gone pass):
#   -l            also run `git-prune-orphans` (local orphans + stale worktrees)
#   -r            also run `git-prune-orphans -r` (SAFE remote + local)
#   -R            also run `git-prune-orphans -R` (AGGRESSIVE remote + local) —
#                 deletes EVERY remote branch with no open PR, regardless of
#                 whether you have it locally. Affects every engineer.
#   -lr / -rl     same as -r alone (safe-mode already chains local)
#   -lR / -Rl     same as -R alone (aggressive already chains local)
# -r and -R are mutually exclusive. No confirmation — the prune commands run
# immediately once the merge completes.
#
# Branch mode handles secondary worktrees: if invoked from a worktree where
# the branch is checked out, after merging it cd's to the main worktree to
# do the checkout/pull/prune (and tries to remove the now-stale worktree).
git-merge-pr-clean() {
  local prune_local=0 prune_remote_mode="" pr_arg=""
  while (( $# > 0 )); do
    case "$1" in
      -l)
        prune_local=1; shift ;;
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
      -*)
        echo "Error: unknown flag '$1'" >&2; return 2 ;;
      *)
        if [[ -n "$pr_arg" ]]; then
          echo "Error: multiple positional args (already have '$pr_arg')" >&2
          return 2
        fi
        pr_arg="$1"; shift ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  # Helper: invoked at the end of each mode's success path. Remote modes already
  # chain the local pass via git-prune-orphans, so a bare -l only fires when no
  # remote mode is set.
  _post_merge_prune() {
    case "$prune_remote_mode" in
      safe) git-prune-orphans -r ;;
      all)  git-prune-orphans -R ;;
      "")   (( prune_local )) && git-prune-orphans ;;
    esac
  }

  if [[ -n "$pr_arg" ]]; then
    # PR-number mode: merge by API, then sync local default if we're on it
    local pr_info pr_state pr_mergeable
    pr_info=$(gh pr view "$pr_arg" --json state,mergeable -q '.state + " " + .mergeable' 2>/dev/null) || {
      echo "Error: PR #$pr_arg not found" >&2
      return 1
    }
    read -r pr_state pr_mergeable <<< "$pr_info"
    if [[ "$pr_state" != "OPEN" ]]; then
      echo "Error: PR #$pr_arg is $pr_state (not OPEN)" >&2
      return 1
    fi
    if [[ "$pr_mergeable" == "CONFLICTING" ]]; then
      echo "Error: PR #$pr_arg has merge conflicts. Resolve before merging." >&2
      return 1
    fi
    if [[ "$pr_mergeable" == "UNKNOWN" ]]; then
      echo "Error: PR #$pr_arg mergeability still computing on GitHub. Retry in a few seconds." >&2
      return 1
    fi

    gh pr merge "$pr_arg" -s --admin || return 1

    local current
    current=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [[ "$current" == "$default" ]]; then
      git pull || return 1
      git-prune-gone
    fi
    _post_merge_prune
    return 0
  fi

  # Branch mode: merge PR for the current branch
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
    echo "Error: detached HEAD" >&2
    return 1
  }

  if [[ "$branch" == "$default" ]]; then
    echo "Error: on default branch '$default' — pass a PR number or switch to a feature branch" >&2
    return 1
  fi

  if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "Error: uncommitted changes in working tree. Commit or stash first." >&2
    return 1
  fi

  if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    echo "Error: untracked files present. Commit, stash, or clean first." >&2
    return 1
  fi

  local upstream
  upstream=$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null) || {
    echo "Error: branch '$branch' has no upstream. Push first." >&2
    return 1
  }

  local ahead
  ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo 0)
  if (( ahead > 0 )); then
    echo "Error: $ahead unpushed commit(s) on '$branch'. Push before merging." >&2
    return 1
  fi

  local pr_info pr_state pr_mergeable
  pr_info=$(gh pr view --json state,mergeable -q '.state + " " + .mergeable' 2>/dev/null) || {
    echo "Error: no PR found for '$branch'" >&2
    return 1
  }
  read -r pr_state pr_mergeable <<< "$pr_info"
  if [[ "$pr_state" != "OPEN" ]]; then
    echo "Error: PR is $pr_state (not OPEN)" >&2
    return 1
  fi
  if [[ "$pr_mergeable" == "CONFLICTING" ]]; then
    echo "Error: PR for '$branch' has merge conflicts. Resolve before merging." >&2
    return 1
  fi
  if [[ "$pr_mergeable" == "UNKNOWN" ]]; then
    echo "Error: PR mergeability still computing on GitHub. Retry in a few seconds." >&2
    return 1
  fi

  # Detect worktree: if we're not in the main worktree, the local checkout
  # of $default lives there, not here.
  local current_wt main_wt in_secondary=0
  current_wt=$(git rev-parse --show-toplevel)
  main_wt=$(git worktree list --porcelain | awk '/^worktree / {print $2; exit}')
  [[ "$current_wt" != "$main_wt" ]] && in_secondary=1

  gh pr merge -s --admin || return 1

  if (( in_secondary )); then
    echo "==> Secondary worktree detected; syncing in main at $main_wt"
    cd "$main_wt" || return 1
    if git worktree remove "$current_wt" 2>/dev/null; then
      echo "Removed worktree: $current_wt"
    else
      echo "Note: worktree at $current_wt not removed (likely has untracked/unmerged content); '$branch' won't prune locally until you clean it up." >&2
    fi
  fi

  git checkout "$default" || return 1
  git pull || return 1
  git-prune-gone
  _post_merge_prune
}

# Print branches "related to" a specific PR — the PR head branch plus any local
# branches whose unique commits appear (by patch-id) in the PR head branch's
# history. Read-only; emits one branch name per line, head branch first.
#
# Independence from cherry-pick `-x` markers: discovery is by patch-id, so it
# catches cherry-picks made without `-x` AND cross-checks `-x`-marked ones.
#
# Usage:
#   git-pr-related-branches <pr-number>
git-pr-related-branches() {
  local pr="$1"
  if [[ -z "$pr" ]]; then
    echo "Usage: git-pr-related-branches <pr-number>" >&2
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
}

# Merge a specific PR (admin override), then clean up ONLY the branches and
# worktrees related to that PR — the PR head branch plus any local branches
# whose commits cherry-picked into it (discovered by patch-id, no `-x`
# required). Other concurrent sessions' worktrees/branches are left untouched
# by construction.
#
# Designed for the case where multiple Claude sessions share a repo: existing
# global pruners (git-prune-gone, git-prune-local-orphans) would reap state
# belonging to OTHER live sessions; this command stays scoped to one PR.
#
# Usage:
#   git-merge-pr-clean-scoped <pr-number>            — merge and clean
#   git-merge-pr-clean-scoped <pr-number> --dry-run  — print plan; no merge, no delete
git-merge-pr-clean-scoped() {
  local dry_run=0 pr=""
  while (( $# > 0 )); do
    case "$1" in
      --dry-run) dry_run=1; shift ;;
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
    echo "Usage: git-merge-pr-clean-scoped <pr-number> [--dry-run]" >&2
    return 2
  fi

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  local current
  current=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ "$current" != "$default" ]]; then
    echo "Error: must be on default branch '$default' (current: '$current')" >&2
    return 1
  fi

  # Validate PR state up front (skipped in dry-run only if PR is closed/merged —
  # still useful to preview which branches the cleanup would touch).
  local pr_info pr_state pr_mergeable
  pr_info=$(gh pr view "$pr" --json state,mergeable -q '.state + " " + .mergeable' 2>/dev/null) || {
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
      echo "Error: PR #$pr mergeability still computing on GitHub. Retry in a few seconds." >&2
      return 1
    fi
  fi

  # Discover related branches BEFORE merging so the session branch's commits
  # are still distinct from default — post-merge the patch-id trace would be
  # noisy or empty.
  local related
  related=$(git-pr-related-branches "$pr") || return 1
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
  git pull || return 1

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
#   git-remote-orphans         — LIST remote branches on origin with no open PR
#   git-prune-remote-orphans   — DELETE those remote branches (push --delete).
#                                Aggressive; same as `git-prune-orphans -R` minus
#                                the chained local prune. Affects everyone.
#   git-local-orphans          — LIST local branches with no corresponding remote
#                                branch on origin
#   git-prune-local-orphans    — DELETE local-orphan branches AND remove the
#                                worktrees that hold them. Also picks up branches
#                                checked out in any secondary worktree (so claude
#                                worktrees that were pushed to origin still get
#                                cleaned locally). Never touches origin.
#
# ─────────────────────────────────────────────────────────────────────────────

# List remote branches on origin that have no open PR (and aren't the default).
# Excludes origin/HEAD and the default branch.
git-remote-orphans() {
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
#   git-prune-remote-orphans            — delete
#   git-prune-remote-orphans --dry-run  — print what would be deleted and exit
git-prune-remote-orphans() {
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
  branches=$(git-remote-orphans)

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
git-local-orphans() {
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
    git-prune-remote-orphans "${fwd_args[@]}" || return 1
  elif [[ "$mode_remote" == "safe" ]]; then
    _git_prune_remote_safe "$dry_run" || return 1
  fi

  git-prune-local-orphans "${fwd_args[@]}"
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
  remote_orphans=$(git-remote-orphans | sort -u)
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
#   1. Local branches with no corresponding branch on origin (git-local-orphans)
#   2. Local branches checked out in a secondary worktree (regardless of remote
#      state — so claude worktrees that were pushed to origin still get cleaned
#      locally; the remote branch stays until you run git-prune-remote-orphans)
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
# too, run git-prune-remote-orphans separately.
#
# Usage:
#   git-prune-local-orphans            — delete (no confirmation; runs immediately)
#   git-prune-local-orphans --dry-run  — print counts (worktree vs non-worktree) and exit
git-prune-local-orphans() {
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
  local_orphans=$(git-local-orphans)
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

# Merge every open PR in numerical order, then sync and prune. Flow:
#   1. Switch to default branch if not on it (refuses if uncommitted/untracked changes).
#   2. List open PRs and merge each with `gh pr merge -s --admin` in numerical order.
#      Skips PRs that are non-OPEN or CONFLICTING; stops on a hard merge failure.
#   3. `git pull` to sync the now-merged default.
#   4. `git-prune-orphans` (with -r / -R passed through).
#
# Flags:
#   -r            pass -r to git-prune-orphans (SAFE remote + local)
#   -R            pass -R to git-prune-orphans (AGGRESSIVE remote + local)
#   <other>       passed through to `gh pr list` (e.g. --author=@me, --label foo)
#
# Examples:
#   git-all-prs-merged-clean                       # merge every open PR, then local prune
#   git-all-prs-merged-clean -r                    # ... then safe remote + local prune
#   git-all-prs-merged-clean -R --author=@me       # only your PRs; aggressive remote prune
git-all-prs-merged-clean() {
  local prune_remote_mode=""
  local -a gh_args=()
  for arg in "$@"; do
    case "$arg" in
      -r)
        [[ "$prune_remote_mode" == "all" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        prune_remote_mode="safe" ;;
      -R)
        [[ "$prune_remote_mode" == "safe" ]] && { echo "Error: -r and -R are mutually exclusive" >&2; return 2; }
        prune_remote_mode="all" ;;
      *) gh_args+=("$arg") ;;
    esac
  done

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  # 1. Switch to default if not on it
  local current
  current=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ "$current" != "$default" ]]; then
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
      echo "Error: uncommitted changes on '$current'; commit or stash first" >&2
      return 1
    fi
    if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
      echo "Error: untracked files on '$current'; commit, stash, or clean first" >&2
      return 1
    fi
    echo "==> Switching to '$default' (was on '$current')"
    git checkout "$default" || return 1
  fi

  # 2. List open PRs in numerical order, merge each
  local prs
  prs=$(gh pr list --state open --json number --jq '.[].number' "${gh_args[@]}" 2>/dev/null | sort -n) || {
    echo "Error: gh pr list failed" >&2
    return 1
  }

  local count=0 skipped=0
  if [[ -n "$prs" ]]; then
    local pr pr_info pr_state pr_mergeable
    while IFS= read -r pr; do
      [[ -z "$pr" ]] && continue
      pr_info=$(gh pr view "$pr" --json state,mergeable -q '.state + " " + .mergeable' 2>/dev/null) || {
        echo "PR #$pr: view failed — skipping" >&2
        skipped=$((skipped + 1))
        continue
      }
      read -r pr_state pr_mergeable <<< "$pr_info"
      if [[ "$pr_state" != "OPEN" ]]; then
        echo "PR #$pr: $pr_state — skipping"
        skipped=$((skipped + 1))
        continue
      fi
      if [[ "$pr_mergeable" == "CONFLICTING" ]]; then
        echo "PR #$pr: CONFLICTING — skipping"
        skipped=$((skipped + 1))
        continue
      fi
      echo "==> Merging PR #$pr"
      if gh pr merge "$pr" -s --admin; then
        count=$((count + 1))
      else
        echo "Failed to merge PR #$pr — stopping (merged $count before failure)" >&2
        return 1
      fi
    done <<< "$prs"
    echo "==> Merged $count PR(s)$( (( skipped > 0 )) && echo "; $skipped skipped" )."
  else
    echo "No open PRs."
  fi

  # 3. Pull synced default
  git pull || return 1

  # 4. Prune (with -r / -R passthrough)
  case "$prune_remote_mode" in
    safe) git-prune-orphans -r ;;
    all)  git-prune-orphans -R ;;
    "")   git-prune-orphans ;;
  esac
}
