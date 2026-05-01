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

git-pr-merge-clean() {
  gh pr merge -s --admin || return 1
  git checkout master || return 1
  git pull || return 1
  git-prune-gone
}
