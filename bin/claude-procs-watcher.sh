#!/usr/bin/env bash
# Claude Process Watcher
# Monitors vitest processes and auto-kills when memory threshold exceeded
#
# Usage: claude-procs-watcher.sh [start|stop|restart|status]

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

WATCHER_DIR="${HOME}/.claude/procs"
PID_FILE="${WATCHER_DIR}/watcher.pid"
LOG_FILE="${WATCHER_DIR}/watcher.log"
CONFIG_FILE="${WATCHER_DIR}/config"

# Defaults
DEFAULT_THRESHOLD_MB=1024
DEFAULT_INTERVAL=30

# Colors
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'

# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════

ensure_dirs() {
    mkdir -p "$WATCHER_DIR"
}

log() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >> "$LOG_FILE"
}

get_threshold() {
    if [[ -f "$CONFIG_FILE" ]]; then
        grep '^threshold=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_THRESHOLD_MB"
    else
        echo "$DEFAULT_THRESHOLD_MB"
    fi
}

get_interval() {
    if [[ -f "$CONFIG_FILE" ]]; then
        grep '^interval=' "$CONFIG_FILE" 2>/dev/null | cut -d= -f2 || echo "$DEFAULT_INTERVAL"
    else
        echo "$DEFAULT_INTERVAL"
    fi
}

set_config() {
    ensure_dirs
    echo "threshold=${1:-$DEFAULT_THRESHOLD_MB}" > "$CONFIG_FILE"
    echo "interval=${2:-$DEFAULT_INTERVAL}" >> "$CONFIG_FILE"
}

# ═══════════════════════════════════════════════════════════════
# WATCHER LOOP
# ═══════════════════════════════════════════════════════════════

watcher_loop() {
    local threshold_mb=$(get_threshold)
    local interval=$(get_interval)
    
    log "Watcher started (threshold: ${threshold_mb}MB, interval: ${interval}s)"
    
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
        done < <(ps -eo pid,etime,%cpu,%mem,command 2>/dev/null | grep -E 'vitest' | grep -v grep | grep -v 'claude-procs')
        
        local total_mem_mb=$((total_mem_kb / 1024))
        
        # Check if threshold exceeded
        if [[ ${#vitest_pids[@]} -gt 0 && $total_mem_mb -ge $threshold_mb ]]; then
            log "THRESHOLD EXCEEDED: ${total_mem_mb}MB >= ${threshold_mb}MB (${#vitest_pids[@]} processes)"
            
            # Kill processes until under threshold
            for i in "${!vitest_pids[@]}"; do
                local pid="${vitest_pids[$i]}"
                local mem_mb=$((${vitest_mems[$i]} / 1024))
                local short_cmd="${vitest_cmds[$i]:0:50}"
                
                if kill "$pid" 2>/dev/null; then
                    log "Killed PID $pid (${mem_mb}MB) - $short_cmd"
                else
                    log "Failed to kill PID $pid"
                fi
                
                # Recalculate remaining memory
                total_mem_mb=$((total_mem_mb - mem_mb))
                if [[ $total_mem_mb -lt $threshold_mb ]]; then
                    log "Memory now below threshold (${total_mem_mb}MB)"
                    break
                fi
            done
        fi
        
        sleep "$interval"
    done
}

# ═══════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════

cmd_start() {
    local threshold="${1:-}"
    local interval="${2:-}"
    
    ensure_dirs
    
    if [[ -f "$PID_FILE" ]] && ps -p "$(cat "$PID_FILE")" &>/dev/null; then
        echo "Procs watcher already running (PID: $(cat "$PID_FILE"))"
        return 0
    fi
    
    # Save config if provided
    if [[ -n "$threshold" || -n "$interval" ]]; then
        set_config "${threshold:-$(get_threshold)}" "${interval:-$(get_interval)}"
    fi
    
    # Start daemon in background
    nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"
    
    echo "Procs watcher started (PID: $pid)"
    echo "  Threshold: $(get_threshold)MB"
    echo "  Interval: $(get_interval)s"
    echo "  Logs: $LOG_FILE"
}

cmd_stop() {
    local killed=0
    
    # Kill tracked daemon
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" &>/dev/null; then
            kill "$pid" 2>/dev/null || true
            killed=$((killed + 1))
        fi
        rm -f "$PID_FILE"
    fi
    
    # Kill orphaned watcher processes
    local self_pid=$$
    local orphans=$(pgrep -f 'claude-procs-watcher' 2>/dev/null | grep -v "^${self_pid}$" || true)
    if [[ -n "$orphans" ]]; then
        echo "$orphans" | while read pid; do
            kill "$pid" 2>/dev/null && killed=$((killed + 1))
        done
    fi
    
    if [[ $killed -gt 0 ]]; then
        echo "Procs watcher stopped"
    else
        echo "Procs watcher not running"
    fi
}

cmd_restart() {
    cmd_stop
    sleep 0.5
    cmd_start "$@"
}

cmd_status() {
    if [[ -f "$PID_FILE" ]] && ps -p "$(cat "$PID_FILE")" &>/dev/null; then
        echo -e "Procs watcher: ${C_GREEN}RUNNING${C_RESET} (PID: $(cat "$PID_FILE"))"
    else
        echo -e "Procs watcher: ${C_RED}STOPPED${C_RESET}"
    fi
    
    echo "  Threshold: $(get_threshold)MB"
    echo "  Interval: $(get_interval)s"
    
    # Show current vitest memory usage
    local total_mem_kb=0
    local count=0
    local total_system_mem_kb=$(sysctl -n hw.memsize 2>/dev/null)
    total_system_mem_kb=$((total_system_mem_kb / 1024))
    
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local mem_pct=$(echo "$line" | awk '{print $4}')
        local mem_kb=$(echo "$mem_pct $total_system_mem_kb" | awk '{printf "%.0f", $1 * $2 / 100}')
        total_mem_kb=$((total_mem_kb + mem_kb))
        count=$((count + 1))
    done < <(ps -eo pid,etime,%cpu,%mem,command 2>/dev/null | grep -E 'vitest' | grep -v grep | grep -v 'claude-procs')
    
    local total_mem_mb=$((total_mem_kb / 1024))
    echo "  Vitest processes: $count (${total_mem_mb}MB)"
}

cmd_logs() {
    local lines="${1:-50}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "No logs yet"
    fi
}

cmd_config() {
    local threshold="$1"
    local interval="$2"
    
    if [[ -z "$threshold" && -z "$interval" ]]; then
        echo "Current config:"
        echo "  threshold=$(get_threshold)"
        echo "  interval=$(get_interval)"
        echo ""
        echo "Usage: claude-procs-watcher.sh config <threshold_mb> [interval_sec]"
    else
        set_config "${threshold:-$(get_threshold)}" "${interval:-$(get_interval)}"
        echo "Config updated:"
        echo "  threshold=$(get_threshold)"
        echo "  interval=$(get_interval)"
        echo ""
        echo "Restart watcher to apply: claude-procs-watcher.sh restart"
    fi
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true
    
    case "$cmd" in
        start)      cmd_start "$@" ;;
        stop)       cmd_stop ;;
        restart)    cmd_restart "$@" ;;
        status)     cmd_status ;;
        logs)       cmd_logs "$@" ;;
        config)     cmd_config "$@" ;;
        _daemon)    watcher_loop ;;
        help|--help|-h)
            cat <<EOF
claude-procs-watcher.sh - Auto-cleanup vitest processes

Usage: claude-procs-watcher.sh <command> [options]

Commands:
  start [threshold] [interval]  Start watcher daemon
  stop                          Stop watcher daemon
  restart [threshold] [interval] Restart watcher daemon
  status                        Show watcher status
  logs [n]                      Show last n log lines (default: 50)
  config [threshold] [interval] Get/set configuration

Defaults:
  threshold: 1024 MB (combined vitest memory)
  interval: 30 seconds

Examples:
  claude-procs-watcher.sh start          # Start with defaults
  claude-procs-watcher.sh start 2048 60  # 2GB threshold, 60s interval
  claude-procs-watcher.sh status         # Check status
EOF
            ;;
        *)
            echo "Unknown command: $cmd"
            echo "Run '$0 help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
