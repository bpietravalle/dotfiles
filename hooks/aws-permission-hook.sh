#!/usr/bin/env bash
# PreToolUse hook: Semantic AWS command classifier
# stdin: {"tool_name":"Bash","tool_input":{"command":"..."}}
# stdout: JSON with permissionDecision or empty (no opinion)
set -euo pipefail

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

# Only handle Bash tool
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -n "$COMMAND" ]] || exit 0

# Fast exit: no aws in command → no opinion
[[ "$COMMAND" == *aws* ]] || exit 0

# --- Local detection ---

is_local_aws() {
  local cmd="$1"
  # Explicit localhost endpoint
  [[ "$cmd" =~ --endpoint-url[[:space:]]+https?://(localhost|127\.0\.0\.1) ]] && return 0
  # LocalStack / local DynamoDB env markers
  [[ "$cmd" =~ DYNAMO_ENDPOINT=http:// ]] && return 0
  [[ "$cmd" =~ AWS_ACCESS_KEY_ID=test ]] && return 0
  [[ "$cmd" =~ LOCALSTACK ]] && return 0
  return 1
}

# If the whole command targets local, allow everything
if is_local_aws "$COMMAND"; then
  emit_allow "local aws target detected"
fi

# --- Helpers ---

strip_env_prefix() {
  # Remove leading KEY=value pairs
  local seg="$1"
  while [[ "$seg" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*) ]]; do
    seg="${BASH_REMATCH[1]}"
  done
  printf '%s' "$seg"
}

extract_aws_parts() {
  # From a stripped command, extract: service subcommand
  # Skips flags (--foo / -x) and their values
  local cmd="$1"
  local -a tokens
  read -ra tokens <<< "$cmd"

  local found_aws=0 service="" subcommand=""
  local skip_next=0

  for tok in "${tokens[@]}"; do
    if (( skip_next )); then
      skip_next=0
      continue
    fi
    # Skip flags
    if [[ "$tok" == --* ]]; then
      # Flags that take a value
      case "$tok" in
        --profile|--region|--endpoint-url|--output|--query|--cli-input-*|--table-name|--bucket|--key|--queue-url|--function-name|--user-name|--role-name|--cluster|--log-group-name|--stack-name|--topic-arn|--target-arn|--subject|--message|--item|--filter-pattern|--start-time|--end-time)
          skip_next=1
          ;;
      esac
      continue
    fi
    if [[ "$tok" == -* ]]; then
      skip_next=1
      continue
    fi

    if (( ! found_aws )); then
      [[ "$tok" == "aws" ]] && found_aws=1
      continue
    fi

    if [[ -z "$service" ]]; then
      service="$tok"
    elif [[ -z "$subcommand" ]]; then
      subcommand="$tok"
      break
    fi
  done

  printf '%s\n%s' "$service" "$subcommand"
}

classify_aws() {
  local service="$1" subcommand="$2"

  [[ -z "$service" ]] && { printf 'ask'; return; }

  # Denied services entirely
  case "$service" in
    iam|cloudformation|route53|organizations)
      printf 'deny'
      return
      ;;
  esac

  # Check subcommand patterns
  case "$subcommand" in
    # Reads
    list-*|describe-*|get-*|head-*|scan|query|ls|tail|filter-*|receive-message|login|configure|help|wait)
      printf 'allow'
      ;;
    # Destructive
    delete-table|create-table|terminate-*|remove-*|deregister-*|purge-*)
      printf 'deny'
      ;;
    # Writes that need approval
    put-*|update-*|invoke|send-*|publish|start-*|create-*|tag-*|untag-*|enable-*|disable-*|modify-*|run-*)
      printf 'ask'
      ;;
    *)
      # S3 special cases
      if [[ "$service" == "s3" ]]; then
        case "$subcommand" in
          ls)       printf 'allow' ;;
          cp|mv|sync) printf 'ask' ;;
          rm|rb)    printf 'deny' ;;
          *)        printf 'ask' ;;
        esac
      else
        printf 'ask'
      fi
      ;;
  esac
}

# --- Split chained commands and classify ---

# Split on &&, ||, ;
IFS=$'\n' read -r -d '' -a segments < <(
  printf '%s' "$COMMAND" | sed 's/&&/\n/g; s/||/\n/g; s/;/\n/g'
  printf '\0'
) || true

worst="allow"  # Track most restrictive: allow < ask < deny

for seg in "${segments[@]}"; do
  seg=$(echo "$seg" | xargs)  # trim whitespace
  [[ -z "$seg" ]] && continue

  # Skip non-aws segments
  [[ "$seg" == *aws* ]] || continue

  # Check if this segment is local
  if is_local_aws "$seg"; then
    continue  # local segments always allowed
  fi

  stripped=$(strip_env_prefix "$seg")
  parts=$(extract_aws_parts "$stripped")
  service=$(echo "$parts" | head -1)
  subcommand=$(echo "$parts" | tail -1)

  decision=$(classify_aws "$service" "$subcommand")

  # Escalate: deny > ask > allow
  case "$decision" in
    deny)
      worst="deny"
      ;;
    ask)
      [[ "$worst" != "deny" ]] && worst="ask"
      ;;
  esac
done

case "$worst" in
  allow) emit_allow "aws read operation" ;;
  ask)   emit_ask "aws write operation requires approval" ;;
  deny)  emit_deny "aws restricted service or destructive operation" ;;
esac
