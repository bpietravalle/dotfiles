#!/usr/bin/env bash
# PreToolUse hook: shell safety — catches dangerous commands inside loops/conditionals
set -euo pipefail

emit_allow() { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"%s"}}\n' "${1:-allowed}"; exit 0; }
emit_deny()  { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "${1:-denied}"; exit 0; }
emit_ask()   { printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "${1:-needs approval}"; exit 0; }

INPUT=$(cat)
TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -n "$COMMAND" ]] || exit 0

# Only activate for compound statements — simple commands are handled by other hooks/patterns
# Check if command starts with a control flow keyword or contains loop/conditional structures
is_compound=0
case "$COMMAND" in
  for\ *|while\ *|until\ *|if\ *|\(\ *|\{\ *) is_compound=1 ;;
esac
# Also check for subshells and inline loops in pipes
if [[ "$COMMAND" =~ \|[[:space:]]*(for|while|until|if|xargs)[[:space:]] ]]; then
  is_compound=1
fi
(( is_compound )) || exit 0

# --- Extract all command segments from the compound statement ---
# Strip control flow keywords and split on delimiters
extract_inner_commands() {
  local cmd="$1"
  # Remove common shell syntax noise
  printf '%s' "$cmd" \
    | sed 's/\bfor\b[^;]*;\s*do\b//g' \
    | sed 's/\bwhile\b[^;]*;\s*do\b//g' \
    | sed 's/\buntil\b[^;]*;\s*do\b//g' \
    | sed 's/\bif\b//g; s/\bthen\b//g; s/\belse\b//g; s/\belif\b//g' \
    | sed 's/\bfi\b//g; s/\bdone\b//g; s/\bdo\b//g' \
    | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g; s/|/\n/g'
}

# --- Deny patterns: always block these ---
DENY_PATTERNS=(
  'rm -rf /'
  'rm -rf /\*'
  'rm -rf ~'
  'rm -rf ~/\*'
  'rm -rf \.'
  'sudo '
  'su '
  'dd '
  'mkfs '
  'chmod -R 000'
  'chmod 777 /'
  'eval '
  '> /dev/sd'
  'curl .\+|.sh'
  'wget .\+|.sh'
)

# --- Ask patterns: prompt user for these ---
ASK_PATTERNS=(
  'rm -rf '
  'rm -r '
  'rmdir '
  'chmod -R '
  'chown '
  'brew install'
  'brew uninstall'
  'brew upgrade'
  'defaults write'
  'nohup '
  'exec '
  'killall '
  'launchctl '
)

# Check each inner command against patterns
worst="allow"

while IFS= read -r segment; do
  # Trim whitespace
  segment=$(echo "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ -z "$segment" ]] && continue

  # Strip leading env var assignments (KEY=value pairs)
  local_seg="$segment"
  while [[ "$local_seg" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; do
    local_seg="${local_seg#*=}"
    # Skip past the value (quoted or unquoted)
    if [[ "$local_seg" =~ ^\"[^\"]*\" ]]; then
      local_seg="${local_seg#\"*\"}"
    elif [[ "$local_seg" =~ ^\'[^\']*\' ]]; then
      local_seg="${local_seg#\'*\'}"
    else
      local_seg="${local_seg#* }"
    fi
    local_seg=$(echo "$local_seg" | sed 's/^[[:space:]]*//')
  done

  # Check deny patterns
  for pat in "${DENY_PATTERNS[@]}"; do
    if echo "$local_seg" | grep -q "$pat" 2>/dev/null; then
      emit_deny "dangerous command inside compound statement: $pat"
    fi
  done

  # Check ask patterns
  for pat in "${ASK_PATTERNS[@]}"; do
    if echo "$local_seg" | grep -q "$pat" 2>/dev/null; then
      worst="ask"
    fi
  done

done < <(extract_inner_commands "$COMMAND")

case "$worst" in
  ask) emit_ask "compound statement contains commands requiring approval" ;;
  *)   exit 0 ;;  # allow — no dangerous inner commands found
esac
