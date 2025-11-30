#!/bin/bash
# Shell Snapshot Auto-Fixer Watcher
# Monitors ~/.claude/shell-snapshots/ and auto-fixes corrupted files

SNAPSHOT_DIR="$HOME/.claude/shell-snapshots"
PID_FILE="/tmp/claude-shell-watcher.pid"
LOG_FILE="/tmp/claude-shell-watcher.log"
PROCESS_NAME="claude-shell-watcher"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Fix a single file
fix_file() {
    local file="$1"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local fixed=0

    # Pattern 1: Fix rule() function corruption
    # The bug creates: ─"}\n} (closing brace on next line)
    # Fix by removing standalone } lines after the rule function output
    if grep -q '─"}' "$file" 2>/dev/null; then
        # Remove any line that is just } immediately after a line ending with ─"}
        sed -i.bak -e '/─"}$/{ n; /^}$/d; }' "$file"
        rm -f "${file}.bak"
        fixed=1
    fi

    # Pattern 2: Scan lines 4800-5200 for standalone } or )
    # These are corruption artifacts, not legitimate code
    local line_num
    for line_num in $(sed -n '4800,5200{=;p}' "$file" 2>/dev/null | sed 'N;s/\n/ /' | grep -E '^[0-9]+ [[:space:]]*[})][[:space:]]*$' | cut -d' ' -f1); do
        sed -i.bak "${line_num}d" "$file"
        rm -f "${file}.bak"
        fixed=1
    done

    if [[ $fixed -eq 1 ]]; then
        echo "[$timestamp] ✓ Fixed: $(basename "$file")" | tee -a "$LOG_FILE"
        return 0
    fi
    return 1
}

# Watch function (uses fswatch on macOS)
watch_and_fix() {
    echo "[$PROCESS_NAME] Starting watcher on $SNAPSHOT_DIR"
    echo "[$PROCESS_NAME] Logging to: $LOG_FILE"
    echo "[$PROCESS_NAME] PID: $$" | tee -a "$LOG_FILE"

    # Check if fswatch is installed
    if ! command -v fswatch &> /dev/null; then
        echo -e "${RED}Error: fswatch not installed${NC}"
        echo "Install with: brew install fswatch"
        exit 1
    fi

    # Watch for new files (existing files already fixed in start())
    # --latency 0.01 = check every 10ms instead of 1s default
    fswatch -0 --event Created --event Updated --latency 0.01 "$SNAPSHOT_DIR" 2>/dev/null | while read -d "" filepath; do
        local filename=$(basename "$filepath")
        # Only process .sh files, skip temp files (.bak, .!*, etc.)
        if [[ "$filepath" == *.sh ]] && [[ ! "$filepath" == *.bak ]] && [[ ! "$filename" == .!* ]]; then
            local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
            echo "[$timestamp] 🔍 Detected: $filename" | tee -a "$LOG_FILE"
            # Minimal delay to ensure file is fully written
            sleep 0.01
            fix_file "$filepath"
        fi
    done
}

# Start watcher
start() {
    local foreground="${1:-}"

    # Auto-stop any existing process first (clean slate)
    if [ "$foreground" != "--foreground" ] && [ "$foreground" != "-f" ]; then
        if [ -f "$PID_FILE" ]; then
            local pid=$(cat "$PID_FILE")
            if ps -p "$pid" > /dev/null 2>&1; then
                echo -e "${YELLOW}Stopping existing watcher (PID: $pid)...${NC}"
                stop > /dev/null 2>&1
            else
                echo -e "${YELLOW}Removing stale PID/log files${NC}"
                rm -f "$PID_FILE" "$LOG_FILE"
            fi
        fi
    fi

    # Fix existing corrupted files before starting watcher
    echo -e "${BLUE}Fixing existing corrupted files...${NC}"
    local fixed=0
    while IFS= read -r file; do
        if fix_file "$file"; then
            fixed=$((fixed + 1))
        fi
    done < <(find "$SNAPSHOT_DIR" -name "*.sh" -type f 2>/dev/null)
    echo -e "${GREEN}Fixed $fixed existing file(s)${NC}"
    echo ""

    # Foreground mode - watch directly (Ctrl+C to stop)
    if [ "$foreground" = "--foreground" ] || [ "$foreground" = "-f" ]; then
        echo -e "${GREEN}Starting in FOREGROUND mode (Ctrl+C to stop)${NC}"
        echo -e "${BLUE}Watching: $SNAPSHOT_DIR${NC}"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        watch_and_fix
        return 0
    fi

    # Background mode - start with nohup
    nohup bash -c "
        SNAPSHOT_DIR='$SNAPSHOT_DIR'
        LOG_FILE='$LOG_FILE'
        PROCESS_NAME='$PROCESS_NAME'

        $(declare -f fix_file)
        $(declare -f watch_and_fix)

        watch_and_fix
    " > /dev/null 2>&1 &

    local pid=$!
    echo "$pid" > "$PID_FILE"

    # Verify it started
    sleep 0.5
    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Watcher started in BACKGROUND${NC}"
        echo -e "  PID: ${BLUE}$pid${NC}"
        echo -e "  Log: ${BLUE}$LOG_FILE${NC}"
        echo -e "  Process: ${BLUE}$PROCESS_NAME${NC}"
        echo -e "  ${YELLOW}Use 'stop' to stop, 'logs' to view activity${NC}"
    else
        echo -e "${RED}✗ Failed to start watcher${NC}"
        rm -f "$PID_FILE"
        return 1
    fi
}

# Stop watcher
stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo -e "${YELLOW}Watcher not running (no PID file)${NC}"
        return 1
    fi

    local pid=$(cat "$PID_FILE")

    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${YELLOW}Watcher not running (stale PID: $pid)${NC}"
        rm -f "$PID_FILE"
        return 1
    fi

    echo -e "${YELLOW}Stopping watcher (PID: $pid)${NC}"

    # Kill process and all children
    pkill -P "$pid" 2>/dev/null
    kill "$pid" 2>/dev/null

    # Wait for process to die
    local count=0
    while ps -p "$pid" > /dev/null 2>&1 && [ $count -lt 5 ]; do
        sleep 0.5
        count=$((count + 1))
    done

    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${RED}Force killing...${NC}"
        kill -9 "$pid" 2>/dev/null
    fi

    rm -f "$PID_FILE"

    # Clean up log file
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        echo -e "${GREEN}✓ Watcher stopped (PID file and log deleted)${NC}"
    else
        echo -e "${GREEN}✓ Watcher stopped${NC}"
    fi
}

# Restart watcher
restart() {
    echo "Restarting watcher..."
    stop
    sleep 1
    start
}

# Status check
status() {
    echo -e "${BLUE}Shell Snapshot Watcher Status${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check PID file
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            echo -e "Status: ${GREEN}RUNNING${NC}"
            echo -e "PID: ${BLUE}$pid${NC}"

            # Get process info
            local uptime=$(ps -o etime= -p "$pid" | tr -d ' ')
            echo -e "Uptime: ${BLUE}$uptime${NC}"

            # Count processes
            local process_count=$(pgrep -f "$PROCESS_NAME" | wc -l | tr -d ' ')
            echo -e "Processes: ${BLUE}$process_count${NC}"
        else
            echo -e "Status: ${RED}STOPPED${NC} (stale PID: $pid)"
        fi
    else
        echo -e "Status: ${RED}STOPPED${NC}"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "${BLUE}Temp Files${NC}"

    # PID file status
    if [ -f "$PID_FILE" ]; then
        local pid_age=$(( $(date +%s) - $(stat -f %m "$PID_FILE" 2>/dev/null || echo 0) ))
        local pid_age_human=""
        if [ $pid_age -ge 3600 ]; then
            pid_age_human="$((pid_age / 3600))h ago"
        elif [ $pid_age -ge 60 ]; then
            pid_age_human="$((pid_age / 60))m ago"
        else
            pid_age_human="${pid_age}s ago"
        fi
        echo -e "PID file: ${GREEN}EXISTS${NC} ($pid_age_human)"
        echo "  Path: $PID_FILE"
    else
        echo -e "PID file: ${YELLOW}MISSING${NC}"
        echo "  Path: $PID_FILE"
    fi

    # Log file status
    if [ -f "$LOG_FILE" ]; then
        local log_age=$(( $(date +%s) - $(stat -f %m "$LOG_FILE" 2>/dev/null || echo 0) ))
        local log_age_human=""
        if [ $log_age -ge 3600 ]; then
            log_age_human="$((log_age / 3600))h ago"
        elif [ $log_age -ge 60 ]; then
            log_age_human="$((log_age / 60))m ago"
        else
            log_age_human="${log_age}s ago"
        fi
        local log_size=$(wc -l < "$LOG_FILE" | tr -d ' ')
        echo -e "Log file: ${GREEN}EXISTS${NC} ($log_age_human, $log_size lines)"
        echo "  Path: $LOG_FILE"
        echo ""
        echo "Recent activity (last 10 lines):"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        tail -10 "$LOG_FILE" 2>/dev/null || echo "No recent activity"
    else
        echo -e "Log file: ${YELLOW}MISSING${NC}"
        echo "  Path: $LOG_FILE"
    fi
}

# View logs
logs() {
    local lines="${1:-50}"
    if [ -f "$LOG_FILE" ]; then
        local log_lines=$(wc -l < "$LOG_FILE" | tr -d ' ')
        if [ "$log_lines" -eq 0 ]; then
            echo -e "${YELLOW}Log file exists but is empty (no files fixed yet)${NC}"
            echo "  Path: $LOG_FILE"
        else
            echo -e "${BLUE}Showing last $lines of $log_lines total log lines:${NC}"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            tail -n "$lines" "$LOG_FILE"
        fi
    else
        echo -e "${YELLOW}No log file found${NC}"
        echo "  Expected path: $LOG_FILE"
        echo "  (Watcher may not have been started yet)"
    fi
}

# Clear logs
clear_logs() {
    if [ -f "$LOG_FILE" ]; then
        > "$LOG_FILE"
        echo -e "${GREEN}✓ Logs cleared${NC}"
    else
        echo "No log file found"
    fi
}

# Main command dispatcher
case "${1:-status}" in
    start)
        start "$2"
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status|s)
        status
        ;;
    logs|l)
        logs "${2:-50}"
        ;;
    help|h|--help|-h)
        echo "Shell Snapshot Auto-Fixer Watcher"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  start [-f|--foreground]"
        echo "               Start the watcher daemon"
        echo "               • Auto-stops any existing watcher first"
        echo "               • Deletes old PID/log files (clean slate)"
        echo "               • Fixes ALL existing corrupted files"
        echo "               • Starts watching for new files"
        echo "               • -f, --foreground: Run in foreground (watch it work!)"
        echo "  stop         Stop the watcher daemon"
        echo "               • Kills process + deletes PID/log files"
        echo "  restart      Restart the watcher daemon (stop + start)"
        echo "  status, s    Show watcher status (default)"
        echo "  logs [n]     Show last n lines of log (default: 50)"
        echo "  help, h      Show this help message"
        echo ""
        echo "Process Info:"
        echo "  Name: $PROCESS_NAME"
        echo "  PID file: $PID_FILE (auto-deleted on stop)"
        echo "  Log file: $LOG_FILE (auto-deleted on stop/start)"
        echo ""
        echo "Requirements:"
        echo "  - fswatch (install with: brew install fswatch)"
        echo ""
        echo "Behavior:"
        echo "  • Watches: $SNAPSHOT_DIR"
        echo "  • Auto-fixes line 4903 corruption in .sh files"
        echo "  • Event-based (efficient, no polling)"
        echo "  • Clean lifecycle (no leftover files)"
        echo ""
        echo "Examples:"
        echo "  $0 start -f       # Watch in foreground (see it work!)"
        echo "  $0 start          # Run in background"
        echo "  $0 status         # Check if running"
        echo "  $0 logs 100       # View last 100 log lines"
        echo "  $0 stop           # Stop + cleanup PID/log"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
