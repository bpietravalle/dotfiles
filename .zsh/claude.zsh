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
  shift 2>/dev/null || true

  case "$cmd" in
    # Snapshot management
    snap|snapshot)
      _claude_snap "$@"
      ;;

    # Unified watcher control
    watch)
      _claude_watch "$@"
      ;;

    # Permissions management
    perm|permissions)
      claude-permissions.js "$@"
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
# SNAP - Snapshot Management
# ═══════════════════════════════════════════════════════════════

_claude_snap() {
  local subcmd="${1:-status}"
  shift 2>/dev/null || true
  
  case "$subcmd" in
    status)
      local total=0 corrupted=0
      for f in "$CLAUDE_SNAPSHOT_DIR"/*.sh(N); do
        [[ -f "$f" ]] || continue
        total=$((total + 1))
        sed -n '4903p' "$f" 2>/dev/null | grep -qx '[[:space:]]*}[[:space:]]*' && corrupted=$((corrupted + 1))
      done
      echo "Snapshots: $total total, $corrupted corrupted"
      [[ $corrupted -gt 0 ]] && echo "Run 'claude-util snap fix' to repair"
      ;;
    fix)
      claude-shell-cleanup.sh fix
      ;;
    nuke)
      rm -f "$CLAUDE_SNAPSHOT_DIR"/*.sh 2>/dev/null
      echo "All snapshots deleted"
      ;;
    help|--help|-h)
      cat <<'EOF'
claude-util snap - Snapshot management

Usage: claude-util snap <command>

Commands:
  status    Show snapshot health
  fix       Repair corrupted snapshots
  nuke      Delete all snapshots (emergency)
EOF
      ;;
    *)
      echo "Unknown snap command: $subcmd"
      echo "Run 'claude-util snap help' for usage"
      return 1
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════
# WATCH - Unified Watcher Control
# ═══════════════════════════════════════════════════════════════

_claude_watch() {
  local subcmd="${1:-list}"
  shift 2>/dev/null || true
  
  case "$subcmd" in
    list|ls)
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "Claude Watchers"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      printf "%-12s %-10s %s\n" "WATCHER" "STATUS" "DETAILS"
      echo "────────────────────────────────────────────────────────────"
      
      # Shell watcher
      if [[ -f /tmp/claude-shell-watcher.pid ]] && ps -p "$(cat /tmp/claude-shell-watcher.pid 2>/dev/null)" &>/dev/null; then
        printf "%-12s \033[0;32m%-10s\033[0m %s\n" "shell" "RUNNING" "Snapshot monitoring"
      else
        printf "%-12s \033[0;31m%-10s\033[0m %s\n" "shell" "STOPPED" "Snapshot monitoring"
      fi
      
      # Monitor watcher
      if [[ -f ~/.claude/monitor/daemon.pid ]] && ps -p "$(cat ~/.claude/monitor/daemon.pid 2>/dev/null)" &>/dev/null; then
        printf "%-12s \033[0;32m%-10s\033[0m %s\n" "monitor" "RUNNING" "Claude instance monitoring"
      else
        printf "%-12s \033[0;31m%-10s\033[0m %s\n" "monitor" "STOPPED" "Claude instance monitoring"
      fi
      
      # Procs watcher
      if [[ -f ~/.claude/procs/watcher.pid ]] && ps -p "$(cat ~/.claude/procs/watcher.pid 2>/dev/null)" &>/dev/null; then
        printf "%-12s \033[0;32m%-10s\033[0m %s\n" "procs" "RUNNING" "Vitest memory cleanup"
      else
        printf "%-12s \033[0;31m%-10s\033[0m %s\n" "procs" "STOPPED" "Vitest memory cleanup"
      fi
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      ;;
      
    start)
      local watcher="${1:-all}"
      case "$watcher" in
        all)
          claude-shell-watcher.sh start
          claude-monitor-watcher.sh start
          claude-procs-watcher.sh start
          ;;
        shell)   claude-shell-watcher.sh start ;;
        monitor) claude-monitor-watcher.sh start ;;
        procs)   claude-procs-watcher.sh start "${@:2}" ;;
        *)
          echo "Unknown watcher: $watcher"
          echo "Available: all, shell, monitor, procs"
          return 1
          ;;
      esac
      ;;
      
    stop)
      local watcher="${1:-all}"
      case "$watcher" in
        all)
          claude-shell-watcher.sh stop
          claude-monitor-watcher.sh stop
          claude-procs-watcher.sh stop
          ;;
        shell)   claude-shell-watcher.sh stop ;;
        monitor) claude-monitor-watcher.sh stop ;;
        procs)   claude-procs-watcher.sh stop ;;
        *)
          echo "Unknown watcher: $watcher"
          echo "Available: all, shell, monitor, procs"
          return 1
          ;;
      esac
      ;;
      
    restart)
      local watcher="${1:-all}"
      case "$watcher" in
        all)
          claude-shell-watcher.sh restart
          claude-monitor-watcher.sh restart
          claude-procs-watcher.sh restart
          ;;
        shell)   claude-shell-watcher.sh restart ;;
        monitor) claude-monitor-watcher.sh restart ;;
        procs)   claude-procs-watcher.sh restart "${@:2}" ;;
        *)
          echo "Unknown watcher: $watcher"
          echo "Available: all, shell, monitor, procs"
          return 1
          ;;
      esac
      ;;
      
    status)
      local watcher="${1:-}"
      if [[ -z "$watcher" ]]; then
        _claude_watch list
      else
        case "$watcher" in
          shell)   claude-shell-watcher.sh status ;;
          monitor) claude-monitor-watcher.sh status ;;
          procs)   claude-procs-watcher.sh status ;;
          *)
            echo "Unknown watcher: $watcher"
            echo "Available: shell, monitor, procs"
            return 1
            ;;
        esac
      fi
      ;;
      
    logs)
      local watcher="${1:-}"
      local lines="${2:-50}"
      case "$watcher" in
        shell)   claude-shell-watcher.sh logs "$lines" 2>/dev/null || echo "No logs" ;;
        monitor) claude-monitor-watcher.sh logs "$lines" ;;
        procs)   claude-procs-watcher.sh logs "$lines" ;;
        "")
          echo "Usage: claude-util watch logs <watcher> [lines]"
          echo "Available: shell, monitor, procs"
          ;;
        *)
          echo "Unknown watcher: $watcher"
          ;;
      esac
      ;;
      
    # Monitor shortcuts
    -f|foreground)
      claude-monitor-watcher.sh foreground
      ;;
    -fv)
      claude-monitor-watcher.sh -fv
      ;;
    goto)
      claude-monitor-watcher.sh goto "$@"
      ;;
    back)
      claude-monitor-watcher.sh back
      ;;
      
    help|--help|-h)
      cat <<'EOF'
claude-util watch - Unified watcher control

Usage: claude-util watch <command> [watcher] [options]

Commands:
  list              Show all watcher statuses (default)
  start [watcher]   Start watcher(s) (default: all)
  stop [watcher]    Stop watcher(s) (default: all)
  restart [watcher] Restart watcher(s) (default: all)
  status [watcher]  Show detailed status
  logs <watcher> [n] Show last n log lines

Watchers:
  all      All watchers
  shell    Snapshot monitoring
  monitor  Claude instance monitoring
  procs    Vitest memory cleanup

Monitor Shortcuts:
  -f       Run monitor in foreground
  -fv      Run monitor verbose dashboard
  goto     Jump to Claude instance
  back     Return from instance

Examples:
  claude-util watch                   # List all statuses
  claude-util watch start             # Start all watchers
  claude-util watch start procs 2048  # Start procs with 2GB threshold
  claude-util watch stop monitor      # Stop only monitor
  claude-util watch -fv               # Verbose dashboard
EOF
      ;;
      
    *)
      echo "Unknown watch command: $subcmd"
      echo "Run 'claude-util watch help' for usage"
      return 1
      ;;
  esac
}

# ═══════════════════════════════════════════════════════════════
# INTERNAL FUNCTIONS
# ═══════════════════════════════════════════════════════════════

_claude_health() {
  # Deprecated - use 'claude-util snap status' and 'claude-util watch list'
  echo "Note: Use 'claude-util snap status' for snapshots"
  echo "      Use 'claude-util watch' for watcher status"
  echo ""
  _claude_snap status
  echo ""
  _claude_watch list
}

_claude_health_legacy() {
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

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SNAPSHOT MANAGEMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  snap status         Show snapshot health
  snap fix            Repair corrupted snapshots
  snap nuke           Delete all snapshots (emergency)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WATCHER CONTROL
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  watch               List all watcher statuses
  watch start [w]     Start watcher(s) (all|shell|monitor|procs)
  watch stop [w]      Stop watcher(s)
  watch restart [w]   Restart watcher(s)
  watch status [w]    Show detailed status
  watch logs <w> [n]  Show last n log lines

  Watchers:
    shell   - Snapshot monitoring
    monitor - Claude instance monitoring  
    procs   - Vitest memory cleanup (1GB threshold)

  Monitor Shortcuts:
    watch -fv           Verbose dashboard (recommended)
    watch goto <sess>   Jump to session
    watch back          Return to dashboard

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROCESS MANAGEMENT
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  procs               Show help
  procs list [opts]   List processes (--all --oldest --max-mem --count N)
  procs test [opts]   List test runners only
  procs kill <pid>    Kill specific process
  procs clean         Interactive cleanup

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OTHER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  perm [cmd]          Permission management (show|merge|diff)
  unfreeze [pane]     Fix frozen pane TTY (run from other session)
  help                Show this help

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXAMPLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  claude-util snap status            # Check snapshot health
  claude-util watch                  # List all watcher statuses
  claude-util watch start            # Start all watchers
  claude-util watch -fv              # Verbose dashboard
  claude-util watch start procs 2048 # Start procs with 2GB threshold
  claude-util procs list --all       # List all processes
  claude-util procs list --oldest    # Longest running
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
  local pids=$(pgrep -f 'claude-monitor-watcher.sh' 2>/dev/null || true)
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
  local mode="${1:-}"
  
  # No args = show help (same as claude-util pattern)
  if [[ -z "$mode" ]]; then
    _claude_procs_help
    return 0
  fi
  
  shift 2>/dev/null || true
  
  case "$mode" in
    list|ls)
      _claude_procs_list "$@"
      ;;
    test|tests)
      _claude_procs_list --filter test "$@"
      ;;
    agent|agents)
      _claude_procs_list --filter agent "$@"
      ;;
    kill)
      _claude_procs_kill "$@"
      ;;
    clean|cleanup)
      _claude_procs_interactive_cleanup
      ;;
    watch)
      _claude_procs_watch "$@"
      ;;
    help|--help|-h)
      _claude_procs_help
      ;;
    *)
      echo "Unknown command: $mode"
      echo "Run 'claude-procs help' for usage"
      return 1
      ;;
  esac
}

_claude_procs_help() {
  cat <<'EOF'
claude-procs - Manage node/python/agent processes

Usage: claude-procs <command> [options]

Commands:
  list [opts]    List processes (default: top 5)
  test [opts]    List test runners only
  kill <pid>     Kill specific PID
  kill [opts]    Bulk kill with preview (kills process trees)
  clean          Interactive cleanup

Options (list & kill):
  --type, -t T   Filter by type (see below)
  --all, -a      Show all (no limit)
  --oldest       Sort by age (longest first)
  --largest      Sort by memory (highest first)
  --count N      Limit to N results (default: 5)
  --force, -9    Use SIGKILL (kill only)

Types (for --type):
  🔒 claude, daemon, mcp, lsp = protected
  ✅ test, agent = safe to kill
  ⚠️  dev, other = caution

Tracked: node, python, pdm, vitest, jest, pytest, tsx, npx

Auto-Cleanup Daemon:
  claude-util watch start procs [threshold_mb]

Examples:
  claude-procs list --all              # All processes
  claude-procs list --type mcp         # Filter by type
  claude-procs list --oldest           # Longest running
  claude-procs kill --largest --count 3  # Kill top 3 memory hogs
  claude-procs test --oldest           # Shortcut: --type test
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
  
  # Claude Code itself (PROTECTED - never kill)
  if [[ "$cmd" == *"claude"* && "$cmd" != *"claude-"* ]] || \
     [[ "$cmd" == *"/claude "* ]] || \
     [[ "$cmd" == *"anthropic"* ]]; then
    echo "claude"
    return
  fi
  
  # Claude utility daemons/watchers (PROTECTED)
  if [[ "$cmd" == *"claude-"*"watcher"* ]] || \
     [[ "$cmd" == *"claude-shell-cleanup"* ]]; then
    echo "daemon"
    return
  fi
  
  # MCP servers (PROTECTED)
  if [[ "$cmd" == *"mcp"* ]] || [[ "$cwd" == *".claude"* ]] || [[ "$cwd" == *".emle"* ]] || \
     [[ "$cmd" == *"serena"* ]] || [[ "$cmd" == *"playwright"* && "$cmd" == *"server"* ]]; then
    echo "mcp"
    return
  fi
  
  # Language servers (PROTECTED)
  if [[ "$cmd" == *"langserver"* ]] || \
     [[ "$cmd" == *"pyright"* ]] || \
     [[ "$cmd" == *"typescript-language"* ]] || \
     [[ "$cmd" == *"tsserver"* ]] || \
     [[ "$cmd" == *"eslint"*"server"* ]] || \
     [[ "$cmd" == *"pylsp"* ]] || \
     [[ "$cmd" == *"bash-language-server"* ]]; then
    echo "lsp"
    return
  fi
  
  # Test runners (SAFE to kill)
  if [[ "$cmd" == *"vitest"* ]] || \
     [[ "$cmd" == *"jest"* ]] || \
     [[ "$cmd" == *"pytest"* ]] || \
     [[ "$cmd" == *"mocha"* ]] || \
     [[ "$cmd" == *"test"* && "$cmd" == *"run"* ]] || \
     [[ "$cmd" == *"node"*"test"* ]]; then
    echo "test"
    return
  fi
  
  # Agent scripts (SAFE to kill - often orphaned)
  if [[ "$cmd" == *"bash"* && "$cwd" == *"claude"* ]] || \
     [[ "$cmd" == *"tsx"* && "$cmd" == *"run"* ]] || \
     [[ "$cmd" == *"npx"* ]]; then
    echo "agent"
    return
  fi
  
  # Development servers
  if [[ "$cmd" == *"dev"* ]] || \
     [[ "$cmd" == *"watch"* ]] || \
     [[ "$cmd" == *"tsx"* && "$cmd" != *"run"* ]]; then
    echo "dev"
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

_claude_procs_etime_to_hours() {
  local etime="$1"
  local secs=$(_claude_procs_etime_to_seconds "$etime")
  local hours=$((secs / 3600))
  echo "${hours}h"
}

_claude_procs_list() {
  # Parse arguments
  local filter="all"
  local sort_by=""
  local count=0
  local show_all=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --filter|--type|-t)
        filter="$2"
        shift 2
        ;;
      --oldest)
        sort_by="time"
        shift
        ;;
      --max-mem|--largest)
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
      --all|-a)
        show_all=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  # Default count (unless --all)
  if [[ $show_all -eq 1 ]]; then
    count=999999
  elif [[ $count -eq 0 ]]; then
    count=5
  fi
  
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
  done < <(ps -eo pid,etime,%cpu,%mem,command | grep -E 'node|python|pdm|vitest|jest|pytest|tsx|bash.*claude|npx' | grep -v grep | grep -v '_claude_procs')
  
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
        if (( sort_keys[$idx_i] < sort_keys[$idx_j] )); then
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
  printf "%-4s %-5s %6s %4s %5s %-8s %-30s %s\n" "WARN" "PID" "AGE" "CPU%" "MEM%" "TYPE" "LOCATION" "COMMAND"
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
    
    local age=$(_claude_procs_etime_to_hours "$etime")
    printf "%-4s %-5s %6s %4s%% %4s%% %-8s %-30s %s\n" \
      "$warn" "$pid" "$age" "$cpu" "$mem" "$type" "$short_cwd" "$short_cmd"
    
    displayed=$((displayed + 1))
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Showing $displayed of ${#pids[@]} processes"
  echo "Types: 🔒claude/daemon/mcp/lsp=protected  ✅test/agent=safe  ⚠️dev/other=caution"
  echo "⚠️  = Long-running (>5h) or high-memory (>1%) test process"
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
    if [[ "$type" == "claude" ]]; then
      echo "🚫 BLOCKED: This is Claude Code itself - cannot kill!"
      return 1
    fi
    if [[ "$type" == "daemon" ]]; then
      echo "🚫 BLOCKED: This is a Claude utility daemon - use 'claude-util watch stop' instead"
      return 1
    fi
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

# Kill a process tree (children first, then parent)
_claude_procs_kill_tree() {
  local pid="$1"
  local sig="${2:--9}"  # Default to SIGKILL
  local killed=0

  # Find all children recursively using pgrep
  local -a children
  children=($(pgrep -P "$pid" 2>/dev/null))

  # Kill children first (recursively)
  for child in "${children[@]}"; do
    _claude_procs_kill_tree "$child" "$sig"
    killed=$((killed + $?))
  done

  # Kill the parent
  if kill $sig "$pid" 2>/dev/null; then
    return $((killed + 1))
  fi
  return $killed
}

_claude_procs_bulk_kill() {
  # Parse arguments
  local filter="all"
  local sort_by=""
  local count=0
  local force=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --filter|--type|-t)
        filter="$2"
        shift 2
        ;;
      --oldest)
        sort_by="time"
        shift
        ;;
      --max-mem|--largest)
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
      --force|-9)
        force=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  # Default count
  [[ $count -eq 0 ]] && count=5
  
  # Collect processes
  local -a pids etimes cpus mems cmds cwds types warns sort_keys ppids
  
  while IFS= read -r line; do
    local pid=$(echo "$line" | awk '{print $1}')
    local ppid=$(echo "$line" | awk '{print $2}')
    local etime=$(echo "$line" | awk '{print $3}')
    local cpu=$(echo "$line" | awk '{print $4}')
    local mem=$(echo "$line" | awk '{print $5}')
    local cmd=$(echo "$line" | awk '{for(i=6;i<=NF;i++) printf "%s ", $i; print ""}')
    
    local cwd=$(_claude_procs_get_cwd "$pid")
    local type=$(_claude_procs_categorize "$cmd" "$cwd")
    
    # Filter if requested
    if [[ "$filter" != "all" ]] && [[ "$type" != "$filter" ]]; then
      continue
    fi
    
    # Skip protected types
    if [[ "$type" == "claude" ]] || [[ "$type" == "daemon" ]] || [[ "$type" == "mcp" ]] || [[ "$type" == "lsp" ]]; then
      continue
    fi
    
    local warn=$(_claude_procs_should_warn "$type" "$etime" "$mem")

    # Store data
    pids+=("$pid")
    ppids+=("$ppid")
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
  done < <(ps -eo pid,ppid,etime,%cpu,%mem,command | grep -E 'node|python|pdm|vitest|jest|pytest|tsx|bash.*claude|npx' | grep -v grep | grep -v '_claude_procs')
  
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
        if (( sort_keys[$idx_i] < sort_keys[$idx_j] )); then
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
  
  # Kill processes (with their children)
  local kill_sig=""
  [[ $force -eq 1 ]] && kill_sig="-9"
  [[ $force -eq 1 ]] && echo "Killing process trees... (SIGKILL)" || echo "Killing process trees..."
  local killed=0
  local total_killed=0
  for pid in "${kill_pids[@]}"; do
    # Count children before killing
    local child_count=$(pgrep -P "$pid" 2>/dev/null | wc -l | tr -d ' ')

    # Kill the tree
    if _claude_procs_kill_tree "$pid" "$kill_sig"; then
      if [[ $child_count -gt 0 ]]; then
        echo "✅ Killed $pid (+$child_count children)"
        total_killed=$((total_killed + child_count + 1))
      else
        echo "✅ Killed $pid"
        total_killed=$((total_killed + 1))
      fi
      killed=$((killed + 1))
    else
      echo "❌ Failed to kill $pid"
    fi
  done

  echo "Killed $killed process trees ($total_killed total)"
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
  done < <(ps -eo pid,etime,%cpu,%mem,command | grep -E 'node|python|pdm|vitest|jest|pytest|tsx|bash.*claude|npx' | grep -v grep | grep -v '_claude_procs')
  
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

_claude_procs_watch() {
  # Parse arguments
  local threshold_mb=1024
  local interval=30
  local dry_run=0
  local once=0
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --threshold)
        threshold_mb="$2"
        shift 2
        ;;
      --interval)
        interval="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=1
        shift
        ;;
      --once)
        once=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done
  
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔍 Vitest Process Watcher"
  echo "   Threshold: ${threshold_mb}MB combined | Interval: ${interval}s"
  [[ $dry_run -eq 1 ]] && echo "   Mode: DRY RUN (no processes will be killed)"
  echo "   Press Ctrl+C to stop"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo
  
  while true; do
    local total_mem_kb=0
    local -a vitest_pids vitest_mems vitest_cmds
    
    # Get total system memory in KB (macOS)
    local total_system_mem_kb=$(sysctl -n hw.memsize 2>/dev/null)
    total_system_mem_kb=$((total_system_mem_kb / 1024))
    
    # Find vitest processes
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      local pid=$(echo "$line" | awk '{print $1}')
      local mem_pct=$(echo "$line" | awk '{print $4}')
      local cmd=$(echo "$line" | awk '{for(i=5;i<=NF;i++) printf "%s ", $i; print ""}')
      
      # Convert percentage to KB
      local mem_kb=$(echo "$mem_pct $total_system_mem_kb" | awk '{printf "%.0f", $1 * $2 / 100}')
      
      vitest_pids+=("$pid")
      vitest_mems+=("$mem_kb")
      vitest_cmds+=("$cmd")
      total_mem_kb=$((total_mem_kb + mem_kb))
    done < <(ps -eo pid,etime,%cpu,%mem,command | grep -E 'vitest' | grep -v grep | grep -v '_claude_procs')
    
    local total_mem_mb=$((total_mem_kb / 1024))
    local timestamp=$(date '+%H:%M:%S')
    
    if [[ ${#vitest_pids[@]} -eq 0 ]]; then
      echo "[$timestamp] No vitest processes running"
    else
      echo "[$timestamp] Vitest processes: ${#vitest_pids[@]} | Memory: ${total_mem_mb}MB / ${threshold_mb}MB threshold"
      
      # Check if threshold exceeded
      if [[ $total_mem_mb -ge $threshold_mb ]]; then
        echo "⚠️  THRESHOLD EXCEEDED - cleaning up oldest processes..."
        
        # Kill processes until under threshold
        for i in "${!vitest_pids[@]}"; do
          local pid="${vitest_pids[$i]}"
          local mem_mb=$((${vitest_mems[$i]} / 1024))
          local short_cmd="${vitest_cmds[$i]:0:50}"
          
          if [[ $dry_run -eq 1 ]]; then
            echo "   [DRY RUN] Would kill PID $pid (${mem_mb}MB) - $short_cmd"
          else
            if kill "$pid" 2>/dev/null; then
              echo "   ✅ Killed PID $pid (${mem_mb}MB) - $short_cmd"
            else
              echo "   ❌ Failed to kill PID $pid"
            fi
          fi
          
          # Recalculate remaining memory
          total_mem_mb=$((total_mem_mb - mem_mb))
          if [[ $total_mem_mb -lt $threshold_mb ]]; then
            echo "   Memory now below threshold (${total_mem_mb}MB)"
            break
          fi
        done
      fi
    fi
    
    # Exit if --once flag
    [[ $once -eq 1 ]] && break
    
    sleep "$interval"
  done
}
