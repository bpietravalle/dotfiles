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
# Branch mode handles secondary worktrees: if invoked from a worktree where
# the branch is checked out, after merging it cd's to the main worktree to
# do the checkout/pull/prune (and tries to remove the now-stale worktree).
git-merge-pr-clean() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  local pr_arg="${1:-}"

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
}

# Merge ALL open PRs in the current repo. Optional args pass through to
# `gh pr list` (e.g. --author=@me, --label foo). On a feature branch with an
# open PR, that PR is merged first, then we sync default and iterate the rest.
# Stops on the first failure so you can intervene.
#
# Examples:
#   git-all-prs-merged-clean                  # merge every open PR
#   git-all-prs-merged-clean --author=@me     # only your PRs
#   git-all-prs-merged-clean --label ready    # only label-filtered PRs
git-all-prs-merged-clean() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  # If on a feature branch with an open PR, merge it first via branch-mode
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ -n "$branch" && "$branch" != "$default" ]]; then
    if [[ "$(gh pr view --json state -q .state 2>/dev/null)" == "OPEN" ]]; then
      echo "==> Merging current branch PR ($branch)..."
      git-merge-pr-clean || return 1
    fi
  fi

  # Ensure we're on default before iterating
  local current
  current=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [[ "$current" != "$default" ]]; then
    git checkout "$default" || return 1
    git pull || return 1
  fi

  local prs
  prs=$(gh pr list --json number -q '.[].number' "$@" 2>/dev/null) || {
    echo "Error: gh pr list failed" >&2
    return 1
  }

  if [[ -z "$prs" ]]; then
    echo "No open PRs remaining."
    return 0
  fi

  # Iterate via direct gh pr merge — server-side, no local sync needed per PR.
  # Single pull + prune at the end is faster and avoids touching worktrees mid-loop.
  local count=0 fail=0
  while IFS= read -r pr; do
    [[ -z "$pr" ]] && continue
    local pr_info pr_state pr_mergeable
    pr_info=$(gh pr view "$pr" --json state,mergeable -q '.state + " " + .mergeable' 2>/dev/null) || {
      echo "PR #$pr: not found, skipping" >&2
      fail=$((fail + 1))
      continue
    }
    read -r pr_state pr_mergeable <<< "$pr_info"
    if [[ "$pr_state" != "OPEN" ]]; then
      echo "PR #$pr: $pr_state, skipping"
      continue
    fi
    if [[ "$pr_mergeable" == "CONFLICTING" ]]; then
      echo "PR #$pr: CONFLICTING, skipping"
      fail=$((fail + 1))
      continue
    fi
    if [[ "$pr_mergeable" == "UNKNOWN" ]]; then
      echo "PR #$pr: mergeability UNKNOWN (GitHub still computing), skipping"
      fail=$((fail + 1))
      continue
    fi
    echo "==> Merging PR #$pr..."
    if gh pr merge "$pr" -s --admin; then
      count=$((count + 1))
    else
      echo "Stopped at PR #$pr — fix and re-run." >&2
      echo "==> Merged $count PR(s) before failure."
      git pull || true
      git-prune-gone
      return 1
    fi
  done <<< "$prs"

  # Final sync after all merges
  git pull || return 1
  git-prune-gone

  echo "==> Merged $count PR(s)$( (( fail > 0 )) && echo "; $fail unresolved" )."
}
