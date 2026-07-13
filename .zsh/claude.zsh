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


    # TTY recovery (run from another session)
    unfreeze)
      claude-unfreeze "$@"
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
      
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      ;;
      
    start)
      local watcher="${1:-all}"
      case "$watcher" in
        all)
          claude-shell-watcher.sh start
          claude-monitor-watcher.sh start
          ;;
        shell)   claude-shell-watcher.sh start ;;
        monitor) claude-monitor-watcher.sh start ;;
        *)
          echo "Unknown watcher: $watcher"
          echo "Available: all, shell, monitor"
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
          ;;
        shell)   claude-shell-watcher.sh stop ;;
        monitor) claude-monitor-watcher.sh stop ;;
        *)
          echo "Unknown watcher: $watcher"
          echo "Available: all, shell, monitor"
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
          ;;
        shell)   claude-shell-watcher.sh restart ;;
        monitor) claude-monitor-watcher.sh restart ;;
        *)
          echo "Unknown watcher: $watcher"
          echo "Available: all, shell, monitor"
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
          *)
            echo "Unknown watcher: $watcher"
            echo "Available: shell, monitor"
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
        "")
          echo "Usage: claude-util watch logs <watcher> [lines]"
          echo "Available: shell, monitor"
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

Monitor Shortcuts:
  -f       Run monitor in foreground
  -fv      Run monitor verbose dashboard
  goto     Jump to Claude instance
  back     Return from instance

Examples:
  claude-util watch                   # List all statuses
  claude-util watch start             # Start all watchers
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
  watch start [w]     Start watcher(s) (all|shell|monitor)
  watch stop [w]      Stop watcher(s)
  watch restart [w]   Restart watcher(s)
  watch status [w]    Show detailed status
  watch logs <w> [n]  Show last n log lines

  Watchers:
    shell   - Snapshot monitoring
    monitor - Claude instance monitoring

  Monitor Shortcuts:
    watch -fv           Verbose dashboard (recommended)
    watch goto <sess>   Jump to session
    watch back          Return to dashboard

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
OTHER
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  unfreeze [pane]     Fix frozen pane TTY (run from other session)
  help                Show this help

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EXAMPLES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  claude-util snap status            # Check snapshot health
  claude-util watch                  # List all watcher statuses
  claude-util watch start            # Start all watchers
  claude-util watch -fv              # Verbose dashboard
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

