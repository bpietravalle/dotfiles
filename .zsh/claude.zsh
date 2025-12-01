# Claude Code Utilities
# Single entrypoint: claude-util <command> [args]

CLAUDE_SNAPSHOT_DIR="$HOME/.claude/shell-snapshots"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CLAUDE_SETTINGS_LOCAL="$HOME/.claude/settings.local.json"

# ═══════════════════════════════════════════════════════════════
# MAIN ENTRYPOINT
# ═══════════════════════════════════════════════════════════════

claude-util() {
  local cmd="${1:-help}"
  shift 2>/dev/null

  case "$cmd" in
    # Status/health
    status|health)
      _claude_health
      ;;

    # Quick fix
    fix)
      claude-shell-cleanup.sh fix
      claude-shell-watcher.sh restart
      ;;

    # Emergency nuke
    nuke)
      rm -f "$CLAUDE_SNAPSHOT_DIR"/*.sh 2>/dev/null
      echo "All snapshots deleted"
      ;;

    # Watcher management
    watch|watcher)
      local subcmd="${1:-status}"
      claude-shell-watcher.sh "$subcmd" "${@:2}"
      ;;

    # Cleanup management
    clean|cleanup)
      local subcmd="${1:-status}"
      claude-shell-cleanup.sh "$subcmd" "${@:2}"
      ;;

    # Permissions management
    perm|permissions)
      claude-permissions.js "$@"
      ;;

    # Monitor management
    monitor|mon)
      local subcmd="${1:-status}"
      shift 2>/dev/null || true
      case "$subcmd" in
        -f|foreground) claude-monitor-daemon foreground ;;
        -fv)           claude-monitor-daemon -fv ;;
        *)             claude-monitor-daemon "$subcmd" "$@" ;;
      esac
      ;;

    # TTY recovery (run from another session)
    unfreeze)
      claude-unfreeze "$@"
      ;;

    # Process management
    procs|ps|processes)
      claude-procs "$@"
      ;;

    # Help
    help|--help|-h)
      _claude_help
      ;;

    *)
      echo "Unknown command: $cmd"
      echo "Run 'claude-util help' for usage"
      return 1
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════
# INTERNAL FUNCTIONS
# ═══════════════════════════════════════════════════════════════

_claude_health() {
  local total=0 corrupted=0

  for f in "$CLAUDE_SNAPSHOT_DIR"/*.sh(N); do
    [[ -f "$f" ]] || continue
    total=$((total + 1))
    sed -n '4903p' "$f" 2>/dev/null | grep -qx '[[:space:]]*}[[:space:]]*' && corrupted=$((corrupted + 1))
  done

  echo "Snapshots: $total total, $corrupted corrupted"

  if [[ -f /tmp/claude-shell-watcher.pid ]] && ps -p "$(cat /tmp/claude-shell-watcher.pid)" &>/dev/null; then
    echo "Watcher: RUNNING"
  else
    echo "Watcher: STOPPED"
  fi
}

_claude_help() {
  cat <<EOF
claude-util - Claude Code utilities

Usage: claude-util <command> [args]

Commands:
  status              Health check (snapshots + watcher)
  fix                 Fix corrupted snapshots + restart watcher
  nuke                Delete all snapshots (emergency)

  watch [cmd]         Watcher management (start|stop|status|logs)
  clean [cmd]         Cleanup management (fix|delete|status)

  perm show           Show global + local permission counts
  perm merge          Merge global → local (deny > ask > allow)
  perm diff           Show differences in allow arrays
  perm --global show  Show all projects in ~/projects/ ~/dev/
  perm --global diff  Show which projects need merge
  perm --global merge Merge global perms into ALL projects

  monitor start           Start monitoring Claude instances (background daemon)
  monitor stop            Stop monitoring + kill orphaned processes
  monitor restart         Restart monitoring daemon
  monitor status          Show monitor status
  monitor list            List all Claude instances and their state
  monitor goto <session>  Jump to a specific session's Claude pane
  monitor back            Switch back to running monitor dashboard (C-a B)
  monitor -f              Foreground mode with live display (simple)
  monitor -fv             Verbose dashboard mode (output preview, persistent)
  monitor attach          Same as -f
  monitor verbosity [lvl] Get/set notification level (silent|minimal|verbose)
  monitor debug [on|off]  Toggle debug logging (off cleans up log file)
  monitor logs [n]        Show last n lines of debug log (default: 50)

  unfreeze [pane]     Kill monitor + reset frozen pane TTY (run from other session)

  procs list [opts]   List all node/python processes with details
  procs test [opts]   List only test runners (vitest, jest, pytest)
  procs kill <pid>    Kill specific process
  procs clean         Interactive cleanup (safe kill of test processes)

  List options: --oldest | --max-mem | --max-cpu | --count N

  help                Show this help

Verbose Dashboard Keys:
  1-9     Jump to numbered instance (dashboard keeps running)
  r       Refresh display (fix visual glitches)
  q       Quit dashboard
  C-a B   Return to dashboard (tmux binding)

Examples:
  claude-util status
  claude-util fix
  claude-util monitor -fv              # Verbose dashboard (recommended)
  claude-util monitor goto myproject   # Jump to session
  claude-util monitor debug on         # Enable debug logging
  claude-util unfreeze dotfiles:0.1    # Fix frozen pane
  claude-util watch start
  claude-util permissions merge
EOF
}

# ═══════════════════════════════════════════════════════════════
# AUTOSTART (called from .zshrc)
# ═══════════════════════════════════════════════════════════════

claude-watcher-autostart() {
  local pid_file="/tmp/claude-shell-watcher.pid"
  local started=0

  if [[ -f "$pid_file" ]]; then
    if ! ps -p "$(cat "$pid_file")" &>/dev/null; then
      claude-shell-watcher.sh start &>/dev/null
      started=1
    fi
  else
    claude-shell-watcher.sh start &>/dev/null
    started=1
  fi

  # Check for corrupted files
  local corrupted=0
  for f in "$CLAUDE_SNAPSHOT_DIR"/*.sh(N); do
    [[ -f "$f" ]] || continue
    sed -n '4903p' "$f" 2>/dev/null | grep -qx '[[:space:]]*}[[:space:]]*' && corrupted=$((corrupted + 1))
  done

  [[ $started -eq 1 ]] && echo "claude: watcher started"
  [[ $corrupted -gt 0 ]] && echo "claude: $corrupted corrupted snapshot(s) - run 'claude-util fix'"
}

# ═══════════════════════════════════════════════════════════════
# TTY RECOVERY (run from another session if monitor freezes a pane)
# ═══════════════════════════════════════════════════════════════

claude-unfreeze() {
  local target="${1:-}"
  local killed=0

  echo "Killing monitor processes..."

  # Kill any running monitor daemons
  local pids=$(pgrep -f 'claude-monitor-daemon' 2>/dev/null || true)
  if [[ -n "$pids" ]]; then
    echo "$pids" | while read pid; do
      kill "$pid" 2>/dev/null && killed=$((killed + 1))
    done
    echo "  Killed monitor process(es)"
  else
    echo "  No monitor processes found"
  fi

  # Clean up state files
  rm -f ~/.claude/monitor/waiting_count 2>/dev/null
  rm -f ~/.claude/monitor/panel_pane 2>/dev/null
  rm -f /tmp/claude-monitor-* 2>/dev/null
  echo "  Cleaned up state files"

  # If target pane specified, send reset commands
  if [[ -n "$target" ]]; then
    echo "Resetting TTY for pane: $target"
    # Send Ctrl-C + stty sane + clear to restore the terminal
    tmux send-keys -t "$target" C-c 2>/dev/null
    sleep 0.1
    tmux send-keys -t "$target" "stty sane; tput cnorm; clear" Enter 2>/dev/null
    if [[ $? -eq 0 ]]; then
      echo "  Reset commands sent to $target"
    else
      echo "  Failed to send to $target (pane may not exist)"
    fi
  else
    echo ""
    echo "To also reset a frozen pane's TTY, specify target:"
    echo "  claude-unfreeze myproject:0.0"
    echo ""
    echo "List panes: tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}'"
  fi
}

# ═══════════════════════════════════════════════════════════════
# PROCESS MANAGEMENT (find and kill runaway test processes)
# ═══════════════════════════════════════════════════════════════

claude-procs() {
  local mode="${1:-list}"
  shift
  
  case "$mode" in
    list|ls)
      _claude_procs_list "$@"
      ;;
    test|tests)
      _claude_procs_list --filter test "$@"
      ;;
    kill)
      _claude_procs_kill "$@"
      ;;
    clean|cleanup)
      _claude_procs_interactive_cleanup
      ;;
    *)
      _claude_procs_help
      ;;
  esac
}

_claude_procs_help() {
  cat <<'EOF'
claude-procs - Manage node/python processes (find runaway tests)

Usage: claude-procs <command> [options]

Commands:
  list [options]   List all node/python processes with details
  test [options]   List only test runners (vitest, jest, pytest)
  kill <pid>       Kill specific process by PID
  kill [options]   Bulk kill processes (shows preview + confirmation)
  clean            Interactive cleanup (safe kill of test processes)

List Options:
  --oldest         Sort by runtime (longest first)
  --max-mem        Sort by memory usage (highest first)
  --max-cpu        Sort by CPU usage (highest first)
  --count N        Show top N results (default: 5)

Bulk Kill Options:
  Same as list options (--oldest, --max-mem, --max-cpu, --count)
  Shows preview list, then asks for confirmation before killing

Process Info Shown:
  PID       Process ID
  Runtime   How long it's been running
  CPU%      CPU usage
  MEM%      Memory usage
  Type      test/mcp/dev/lsp/other
  Location  Working directory
  Command   What's running

Safety:
  ⚠️  MCP servers are marked and excluded from cleanup
  ⚠️  Claude Code processes are protected
  ✅  Test runners (vitest/jest/pytest) are safe to kill

Examples:
  claude-procs list                    # See all processes (top 5)
  claude-procs list --oldest           # Longest running processes
  claude-procs list --max-mem --count 3  # Top 3 memory hogs
  claude-procs test --oldest           # Longest running tests
  claude-procs clean                   # Interactive cleanup
  claude-procs kill 12345              # Kill specific PID
EOF
}

_claude_procs_get_cwd() {
  local pid="$1"
  # macOS: use lsof to get current working directory
  lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep '^n' | cut -c2- || echo "unknown"
}

_claude_procs_categorize() {
  local cmd="$1"
  local cwd="$2"
  
  # MCP servers
  if [[ "$cmd" == *"mcp"* ]] || [[ "$cwd" == *".claude"* ]]; then
    echo "mcp"
    return
  fi
  
  # Test runners
  if [[ "$cmd" == *"vitest"* ]] || \
     [[ "$cmd" == *"jest"* ]] || \
     [[ "$cmd" == *"pytest"* ]] || \
     [[ "$cmd" == *"test"* && "$cmd" == *"run"* ]]; then
    echo "test"
    return
  fi
  
  # Development servers
  if [[ "$cmd" == *"dev"* ]] || \
     [[ "$cmd" == *"watch"* ]] || \
     [[ "$cmd" == *"tsx"* ]]; then
    echo "dev"
    return
  fi
  
  # Language servers
  if [[ "$cmd" == *"langserver"* ]] || \
     [[ "$cmd" == *"pyright"* ]] || \
     [[ "$cmd" == *"typescript"* ]]; then
    echo "lsp"
    return
  fi
  
  echo "other"
}

_claude_procs_should_warn() {
  local type="$1"
  local etime="$2"
  local mem="$3"
  
  # Extract hours from etime (format: HH:MM:SS or DD-HH:MM:SS)
  local hours=0
  if [[ "$etime" == *-* ]]; then
    # Has days
    hours=$(echo "$etime" | cut -d- -f1)
    hours=$((hours * 24 + $(echo "$etime" | cut -d- -f2 | cut -d: -f1)))
  else
    hours=$(echo "$etime" | cut -d: -f1)
  fi
  
  # Remove leading zeros for arithmetic
  hours=${hours##0}
  [[ -z "$hours" ]] && hours=0
  
  # Warn if test running >5 hours or mem >1%
  if [[ "$type" == "test" ]] && { [[ $hours -ge 5 ]] || (( $(echo "$mem > 1.0" | bc -l 2>/dev/null || echo 0) )); }; then
    echo "⚠️ "
  else
    echo "   "
  fi
}

_claude_procs_etime_to_seconds() {
  local etime="$1"
  local seconds=0
  
  # Parse format: [[dd-]hh:]mm:ss
  if [[ "$etime" == *-* ]]; then
    # Has days: dd-hh:mm:ss
    local days=$(echo "$etime" | cut -d- -f1)
    local rest=$(echo "$etime" | cut -d- -f2)
    local hours=$(echo "$rest" | cut -d: -f1)
    local mins=$(echo "$rest" | cut -d: -f2)
    local secs=$(echo "$rest" | cut -d: -f3)
    seconds=$((days * 86400 + hours * 3600 + mins * 60 + secs))
  else
    # Count colons to determine format
    local colons=$(echo "$etime" | tr -cd ':' | wc -c)
    if [[ $colons -eq 2 ]]; then
      # hh:mm:ss
      local hours=$(echo "$etime" | cut -d: -f1)
      local mins=$(echo "$etime" | cut -d: -f2)
      local secs=$(echo "$etime" | cut -d: -f3)
      seconds=$((hours * 3600 + mins * 60 + secs))
    else
      # mm:ss
      local mins=$(echo "$etime" | cut -d: -f1)
      local secs=$(echo "$etime" | cut -d: -f2)
      seconds=$((mins * 60 + secs))
    fi
  fi
  
  echo "$seconds"
}

_claude_procs_list() {
  # Parse arguments
  local filter="all"
  local sort_by=""
  local count=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --filter)
        filter="$2"
        shift 2
        ;;
      --oldest)
        sort_by="time"
        shift
        ;;
      --max-mem)
        sort_by="mem"
        shift
        ;;
      --max-cpu)
        sort_by="cpu"
        shift
        ;;
      --count)
        count="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  
  # Default count
  [[ $count -eq 0 ]] && count=5
  
  # Collect processes into arrays
  local -a pids etimes cpus mems cmds cwds types warns sort_keys
  
  while IFS= read -r line; do
    # Parse ps output: PID ELAPSED %CPU %MEM COMMAND
    local pid=$(echo "$line" | awk '{print $1}')
    local etime=$(echo "$line" | awk '{print $2}')
    local cpu=$(echo "$line" | awk '{print $3}')
    local mem=$(echo "$line" | awk '{print $4}')
    local cmd=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}')
    
    local cwd=$(_claude_procs_get_cwd "$pid")
    local type=$(_claude_procs_categorize "$cmd" "$cwd")
    
    # Filter if requested
    if [[ "$filter" != "all" ]] && [[ "$type" != "$filter" ]]; then
      continue
    fi
    
    local warn=$(_claude_procs_should_warn "$type" "$etime" "$mem")
    
    # Store data
    pids+=("$pid")
    etimes+=("$etime")
    cpus+=("$cpu")
    mems+=("$mem")
    cmds+=("$cmd")
    cwds+=("$cwd")
    types+=("$type")
    warns+=("$warn")
    
    # Calculate sort key
    case "$sort_by" in
      time)
        local secs=$(_claude_procs_etime_to_seconds "$etime")
        sort_keys+=("$secs")
        ;;
      mem)
        # Remove % and pad for sorting
        sort_keys+=("$(printf "%010.1f" "$mem")")
        ;;
      cpu)
        sort_keys+=("$(printf "%010.1f" "$cpu")")
        ;;
      *)
        sort_keys+=("0")
        ;;
    esac
  done < <(ps -eo pid,etime,%cpu,%mem,command | grep -E 'node|python' | grep -v grep)
  
  # Sort if requested
  if [[ -n "$sort_by" ]]; then
    # Create indices array
    local -a indices
    for i in {1..${#pids[@]}}; do
      indices+=($i)
    done
    
    # Bubble sort (simple for small arrays)
    for ((i = 1; i <= ${#indices[@]}; i++)); do
      for ((j = i + 1; j <= ${#indices[@]}; j++)); do
        local idx_i=${indices[$i]}
        local idx_j=${indices[$j]}
        # Compare sort keys (reverse for descending)
        if [[ "${sort_keys[$idx_i]}" < "${sort_keys[$idx_j]}" ]]; then
          # Swap
          local temp=${indices[$i]}
          indices[$i]=${indices[$j]}
          indices[$j]=$temp
        fi
      done
    done
  else
    # No sorting - use natural order
    local -a indices
    for i in {1..${#pids[@]}}; do
      indices+=($i)
    done
  fi
  
  # Display header
  echo "Node/Python Processes:"
  [[ -n "$sort_by" ]] && echo "Sorted by: $sort_by (showing top $count)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "%-4s %-5s %-12s %4s %5s %-8s %-30s %s\n" "WARN" "PID" "RUNTIME" "CPU%" "MEM%" "TYPE" "LOCATION" "COMMAND"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Display processes (limited by count)
  local displayed=0
  for idx in "${indices[@]}"; do
    [[ $displayed -ge $count ]] && break
    [[ -z "${pids[$idx]}" ]] && continue
    
    local pid="${pids[$idx]}"
    local etime="${etimes[$idx]}"
    local cpu="${cpus[$idx]}"
    local mem="${mems[$idx]}"
    local cmd="${cmds[$idx]}"
    local cwd="${cwds[$idx]}"
    local type="${types[$idx]}"
    local warn="${warns[$idx]}"
    
    # Shorten for display
    local short_cwd="${cwd/#$HOME/~}"
    short_cwd="${short_cwd:0:30}"
    local short_cmd="${cmd:0:60}"
    
    printf "%-4s %-5s %-12s %4s%% %4s%% %-8s %-30s %s\n" \
      "$warn" "$pid" "$etime" "$cpu" "$mem" "$type" "$short_cwd" "$short_cmd"
    
    displayed=$((displayed + 1))
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Showing $displayed of ${#pids[@]} processes"
  echo "Types: test=test runner, mcp=MCP server, dev=dev server, lsp=language server"
  echo "⚠️  = Long-running or high-memory test process (safe to kill)"
}

_claude_procs_kill() {
  # Check if first arg is a PID or a flag
  if [[ "$1" =~ ^[0-9]+$ ]]; then
    # Single PID kill
    local pid="$1"
    
    # Check if process exists
    if ! ps -p "$pid" &>/dev/null; then
      echo "Process $pid not found"
      return 1
    fi
    
    # Get process info
    local info=$(ps -p "$pid" -o command=)
    local cwd=$(_claude_procs_get_cwd "$pid")
    local type=$(_claude_procs_categorize "$info" "$cwd")
    
    # Safety check
    if [[ "$type" == "mcp" ]] || [[ "$type" == "lsp" ]]; then
      echo "⚠️  WARNING: This appears to be an MCP/LSP server!"
      echo "Process: $info"
      read -q "REPLY?Kill anyway? (y/N) "
      echo
      [[ "$REPLY" != "y" ]] && return 1
    fi
    
    echo "Killing process $pid ($type)..."
    kill "$pid" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
      echo "✅ Process $pid killed"
    else
      echo "❌ Failed to kill process $pid (may need sudo)"
    fi
  else
    # Bulk kill with filters
    _claude_procs_bulk_kill "$@"
  fi
}

_claude_procs_bulk_kill() {
  # Parse arguments (same as list)
  local filter="all"
  local sort_by=""
  local count=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --filter)
        filter="$2"
        shift 2
        ;;
      --oldest)
        sort_by="time"
        shift
        ;;
      --max-mem)
        sort_by="mem"
        shift
        ;;
      --max-cpu)
        sort_by="cpu"
        shift
        ;;
      --count)
        count="$2"
        shift 2
        ;;
      *)
        shift
        ;;
    esac
  done
  
  # Default count
  [[ $count -eq 0 ]] && count=5
  
  # Collect processes (same logic as list)
  local -a pids etimes cpus mems cmds cwds types warns sort_keys
  
  while IFS= read -r line; do
    local pid=$(echo "$line" | awk '{print $1}')
    local etime=$(echo "$line" | awk '{print $2}')
    local cpu=$(echo "$line" | awk '{print $3}')
    local mem=$(echo "$line" | awk '{print $4}')
    local cmd=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}')
    
    local cwd=$(_claude_procs_get_cwd "$pid")
    local type=$(_claude_procs_categorize "$cmd" "$cwd")
    
    # Filter if requested
    if [[ "$filter" != "all" ]] && [[ "$type" != "$filter" ]]; then
      continue
    fi
    
    # Skip protected types
    if [[ "$type" == "mcp" ]] || [[ "$type" == "lsp" ]]; then
      continue
    fi
    
    local warn=$(_claude_procs_should_warn "$type" "$etime" "$mem")
    
    # Store data
    pids+=("$pid")
    etimes+=("$etime")
    cpus+=("$cpu")
    mems+=("$mem")
    cmds+=("$cmd")
    cwds+=("$cwd")
    types+=("$type")
    warns+=("$warn")
    
    # Calculate sort key
    case "$sort_by" in
      time)
        local secs=$(_claude_procs_etime_to_seconds "$etime")
        sort_keys+=("$secs")
        ;;
      mem)
        sort_keys+=("$(printf "%010.1f" "$mem")")
        ;;
      cpu)
        sort_keys+=("$(printf "%010.1f" "$cpu")")
        ;;
      *)
        sort_keys+=("0")
        ;;
    esac
  done < <(ps -eo pid,etime,%cpu,%mem,command | grep -E 'node|python' | grep -v grep)
  
  if [[ ${#pids[@]} -eq 0 ]]; then
    echo "No matching processes found"
    return 0
  fi
  
  # Sort if requested
  if [[ -n "$sort_by" ]]; then
    local -a indices
    for i in {1..${#pids[@]}}; do
      indices+=($i)
    done
    
    # Bubble sort (descending)
    for ((i = 1; i <= ${#indices[@]}; i++)); do
      for ((j = i + 1; j <= ${#indices[@]}; j++)); do
        local idx_i=${indices[$i]}
        local idx_j=${indices[$j]}
        if [[ "${sort_keys[$idx_i]}" < "${sort_keys[$idx_j]}" ]]; then
          local temp=${indices[$i]}
          indices[$i]=${indices[$j]}
          indices[$j]=$temp
        fi
      done
    done
  else
    local -a indices
    for i in {1..${#pids[@]}}; do
      indices+=($i)
    done
  fi
  
  # Show what will be killed
  echo "Processes to kill (top $count):"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  printf "%-5s %-12s %4s %5s %-8s %-30s\n" "PID" "RUNTIME" "CPU%" "MEM%" "TYPE" "COMMAND"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  local -a kill_pids
  local displayed=0
  for idx in "${indices[@]}"; do
    [[ $displayed -ge $count ]] && break
    [[ -z "${pids[$idx]}" ]] && continue
    
    local pid="${pids[$idx]}"
    local etime="${etimes[$idx]}"
    local cpu="${cpus[$idx]}"
    local mem="${mems[$idx]}"
    local cmd="${cmds[$idx]}"
    local type="${types[$idx]}"
    
    local short_cmd="${cmd:0:40}"
    printf "%-5s %-12s %4s%% %4s%% %-8s %s\n" \
      "$pid" "$etime" "$cpu" "$mem" "$type" "$short_cmd"
    
    kill_pids+=("$pid")
    displayed=$((displayed + 1))
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # Confirmation
  read -q "REPLY?Kill these $displayed processes? (y/N) "
  echo
  [[ "$REPLY" != "y" ]] && return 0
  
  # Kill processes
  echo "Killing processes..."
  local killed=0
  for pid in "${kill_pids[@]}"; do
    if kill "$pid" 2>/dev/null; then
      echo "✅ Killed $pid"
      killed=$((killed + 1))
    else
      echo "❌ Failed to kill $pid"
    fi
  done
  
  echo "Killed $killed of ${#kill_pids[@]} processes"
}

_claude_procs_interactive_cleanup() {
  echo "Finding test processes to clean up..."
  echo
  
  # Collect test processes into arrays
  local -a test_pids
  local -a test_cmds
  local -a test_times
  local -a test_mems
  local -a test_cwds
  local idx=1
  
  while IFS= read -r line; do
    read pid etime cpu mem cmd <<< "$line"
    local cwd=$(_claude_procs_get_cwd "$pid")
    local type=$(_claude_procs_categorize "$cmd" "$cwd")
    
    if [[ "$type" == "test" ]]; then
      local warn=$(_claude_procs_should_warn "$type" "$etime" "$mem")
      local short_cmd=$(echo "$cmd" | cut -c1-80)
      local short_cwd="${cwd/#$HOME/~}"
      
      echo "[$idx] PID $pid - Runtime: $etime - Mem: ${mem}%"
      echo "    $short_cmd"
      echo "    Location: $short_cwd"
      
      if [[ "$warn" == "⚠️ " ]]; then
        echo "    ⚠️  Recommended for cleanup (long-running or high-memory)"
      fi
      
      echo
      
      test_pids+=("$pid")
      idx=$((idx + 1))
    fi
  done < <(ps -eo pid,etime,%cpu,%mem,command | grep -E 'node|python' | grep -v grep)
  
  if [[ ${#test_pids[@]} -eq 0 ]]; then
    echo "No test processes found"
    return 0
  fi
  
  echo "Enter process numbers to kill (space-separated), or 'all' for all, or 'q' to quit:"
  read -r selection
  
  case "$selection" in
    q|Q)
      echo "Cancelled"
      return 0
      ;;
    all|ALL)
      echo "Killing all test processes..."
      for pid in "${test_pids[@]}"; do
        kill "$pid" 2>/dev/null && echo "✅ Killed $pid"
      done
      ;;
    *)
      for num in $selection; do
        if [[ $num -ge 1 ]] && [[ $num -le ${#test_pids[@]} ]]; then
          local pid="${test_pids[$num]}"
          kill "$pid" 2>/dev/null && echo "✅ Killed $pid"
        fi
      done
      ;;
  esac
}
