#!/usr/bin/env bash
# PreToolUse hook: Owner-scoped gh mutation control
# stdin: {"tool_name":"Bash","tool_input":{"command":"..."}}
# stdout: JSON with permissionDecision or empty (no opinion)
set -euo pipefail

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"
OWNERS_FILE="$HOOK_DIR/gh-allowed-owners.conf"

# --- Emitters ---

emit_allow() {
  local reason="${1:-allowed}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

emit_deny() {
  local reason="${1:-denied}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

emit_ask() {
  local reason="${1:-needs approval}"
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

# --- Read stdin ---

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -n "$COMMAND" ]] || exit 0

# Fast exit: no gh in command
[[ "$COMMAND" == *gh\ * ]] || [[ "$COMMAND" == gh\ * ]] || exit 0

# --- Helpers ---

get_owner_from_flag() {
  local cmd="$1"
  local repo=""
  # Match --repo owner/repo or -R owner/repo
  if [[ "$cmd" =~ (--repo|-R)[[:space:]]+([^[:space:]]+) ]]; then
    repo="${BASH_REMATCH[2]}"
    printf '%s' "${repo%%/*}"
    return
  fi
  return 1
}

get_owner_from_remote() {
  local remote
  remote=$(git remote get-url origin 2>/dev/null) || return 1
  # Handle git@github.com:owner/repo.git and https://github.com/owner/repo.git
  if [[ "$remote" =~ github\.com[:/]([^/]+)/ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return
  fi
  return 1
}

is_allowed_owner() {
  local owner="$1"
  [[ -z "$owner" ]] && return 1
  [[ ! -f "$OWNERS_FILE" ]] && return 1
  grep -qxF "$owner" "$OWNERS_FILE" 2>/dev/null
}

extract_gh_parts() {
  # Extract: noun verb (skip flags)
  local cmd="$1"
  local -a tokens
  read -ra tokens <<< "$cmd"

  local found_gh=0 noun="" verb=""
  local skip_next=0

  for tok in "${tokens[@]}"; do
    if (( skip_next )); then
      skip_next=0
      continue
    fi
    if [[ "$tok" == --* ]]; then
      case "$tok" in
        --repo|--title|--body|--assignee|--label|--milestone|--base|--head|--reviewer|--jq|--template|--json|--limit)
          skip_next=1
          ;;
      esac
      continue
    fi
    if [[ "$tok" == -* ]]; then
      skip_next=1
      continue
    fi

    if (( ! found_gh )); then
      [[ "$tok" == "gh" ]] && found_gh=1
      continue
    fi

    if [[ -z "$noun" ]]; then
      noun="$tok"
    elif [[ -z "$verb" ]]; then
      verb="$tok"
      break
    fi
  done

  printf '%s\n%s' "$noun" "$verb"
}

# --- Classify ---

parts=$(extract_gh_parts "$COMMAND")
noun=$(echo "$parts" | head -1)
verb=$(echo "$parts" | tail -1)

[[ -z "$noun" ]] && exit 0  # can't parse, no opinion

# Non-repo subcommands: always allow
case "$noun" in
  auth|config|extension|alias|completion|help|ssh-key|gpg-key|secret|variable|cache|ruleset|codespace|cs)
    emit_allow "gh utility command"
    ;;
esac

# gh api special handling
if [[ "$noun" == "api" ]]; then
  # Check HTTP method
  if [[ "$COMMAND" =~ (-X|--method)[[:space:]]+(GET|HEAD) ]]; then
    emit_allow "gh api read"
  elif [[ "$COMMAND" =~ (-X|--method)[[:space:]]+(POST|PUT|PATCH|DELETE) ]]; then
    emit_ask "gh api write: $verb"
  fi
  # No explicit method defaults to GET for most endpoints
  emit_allow "gh api (default GET)"
fi

# Read verbs: always allow
case "$verb" in
  list|view|status|diff|checks|search|browse|checkout|develop)
    emit_allow "gh read operation"
    ;;
esac

# Destructive verbs: always ask regardless of owner
case "$verb" in
  close|delete|merge)
    emit_ask "gh destructive: $noun $verb"
    ;;
esac

# Special combo: release create, repo delete
if [[ "$noun" == "release" && "$verb" == "create" ]]; then
  emit_ask "gh release create"
fi
if [[ "$noun" == "repo" && "$verb" == "delete" ]]; then
  emit_ask "gh repo delete"
fi

# Owner-scoped mutations
case "$verb" in
  create|comment|edit|reopen|assign|label|review|unlock|lock|pin|unpin|transfer|ready)
    owner=$(get_owner_from_flag "$COMMAND" || get_owner_from_remote || true)
    if [[ -n "$owner" ]] && is_allowed_owner "$owner"; then
      emit_allow "gh mutation: allowed owner ($owner)"
    else
      emit_ask "gh mutation: $noun $verb (owner: ${owner:-unknown})"
    fi
    ;;
esac

# Fallback: anything else, no opinion
exit 0
