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
