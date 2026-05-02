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
# If the current branch is among the gone ones, switches to the default branch first.
git-prune-gone() {
  git fetch --prune || return 1

  local gone
  gone=$(git for-each-ref --format '%(refname:short) %(upstream:track)' refs/heads \
         | awk '$2 == "[gone]" {print $1}')

  if [[ -z "$gone" ]]; then
    echo "No gone branches."
    return 0
  fi

  local current default
  current=$(git symbolic-ref --short HEAD 2>/dev/null)
  if echo "$gone" | grep -qx "$current"; then
    default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
    : "${default:=master}"
    echo "Switching off '$current' to '$default' before deletion..."
    git switch "$default" || return 1
  fi

  echo "$gone" | xargs git branch -D
}

# Squash-merge the PR for the current branch (admin override), switch to the
# default branch, pull, and prune gone branches. Pre-flight checks fail fast
# rather than leave you in a half-merged state.
git-merge-pr-clean() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "Error: not in a git repo" >&2
    return 1
  }

  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
    echo "Error: detached HEAD" >&2
    return 1
  }

  local default
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
  : "${default:=master}"

  if [[ "$branch" == "$default" ]]; then
    echo "Error: already on default branch '$default' — nothing to merge" >&2
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

  local pr_state
  pr_state=$(gh pr view --json state -q .state 2>/dev/null) || {
    echo "Error: no PR found for '$branch'" >&2
    return 1
  }
  if [[ "$pr_state" != "OPEN" ]]; then
    echo "Error: PR is $pr_state (not OPEN)" >&2
    return 1
  fi

  gh pr merge -s --admin || return 1
  git checkout "$default" || return 1
  git pull || return 1
  git-prune-gone
}
