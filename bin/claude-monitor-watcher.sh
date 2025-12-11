#!/usr/bin/env bash
# Claude Monitor Daemon
# Polls tmux sessions for Claude instances and tracks their state
#
# Usage: claude-monitor-daemon [start|stop|status|list|goto|foreground]

set -euo pipefail

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

MONITOR_DIR="${HOME}/.claude/monitor"
CONFIG_FILE="${MONITOR_DIR}/config.json"
STATE_DIR="${MONITOR_DIR}/states"
PID_FILE="${MONITOR_DIR}/daemon.pid"
LOG_FILE="${MONITOR_DIR}/daemon.log"

# Pane convention: check left pane (pane 0) in windows 0 and 1
# Returns "window.pane" format (e.g., "0.0" or "1.0")
CLAUDE_PANES=("0.0" "1.0")

# Polling interval (seconds)
POLL_INTERVAL=2

# Idle detection (simpler and more reliable than pattern matching)
# If output hasn't changed for this many seconds, Claude is "idle"
# 30s accounts for Claude's thinking time before output
IDLE_THRESHOLD=30

# Optional: hint patterns (for display context, not primary detection)
# These help label WHY Claude is idle, but idle detection is the primary trigger
HINT_PATTERNS=(
    "Allow.*Deny:permission"
    "^>:question"
    "^\?:question"
    "y/n:confirm"
    "Y/n:confirm"
)

# Colors
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_GRAY='\033[0;90m'
C_BOLD='\033[1m'
C_DIM='\033[2m'

# Box drawing
BOX_TL='┌' BOX_TR='┐' BOX_BL='└' BOX_BR='┘'
BOX_H='─' BOX_V='│'
BOX_LT='├' BOX_RT='┤' BOX_TT='┬' BOX_BT='┴' BOX_X='┼'

# ═══════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════

get_debug() {
    if [[ -f "$CONFIG_FILE" ]]; then
        grep -o '"debug"[[:space:]]*:[[:space:]]*true' "$CONFIG_FILE" &>/dev/null && echo "on" || echo "off"
    else
        echo "off"
    fi
}

log() {
    [[ "$(get_debug)" == "off" ]] && return
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $*" >> "$LOG_FILE"
}

ensure_dirs() {
    mkdir -p "$MONITOR_DIR" "$STATE_DIR"
}

get_verbosity() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Simple grep-based JSON parsing (no jq dependency)
        grep -o '"verbosity"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | \
            sed 's/.*"\([^"]*\)"$/\1/' || echo "minimal"
    else
        echo "minimal"
    fi
}

set_verbosity() {
    local level="$1"
    ensure_dirs
    echo "{\"verbosity\": \"$level\"}" > "$CONFIG_FILE"
    echo "Verbosity set to: $level"
}

strip_ansi() {
    # Remove ANSI escape codes
    sed 's/\x1b\[[0-9;]*m//g' | sed 's/\x1b\[[0-9;]*[A-Za-z]//g'
}

# ═══════════════════════════════════════════════════════════════
# TMUX INTERACTION
# ═══════════════════════════════════════════════════════════════

get_tmux_sessions() {
    tmux list-sessions -F "#{session_name}" 2>/dev/null || true
}

get_pane_content() {
    local target="$1"  # Full target like "session:0.0"

    # Capture last 50 lines of pane
    tmux capture-pane -t "$target" -p -S -50 2>/dev/null | strip_ansi || true
}

# Find which pane (if any) in a session is running Claude
# Returns the pane target (e.g., "0.0") or empty if none found
find_claude_pane() {
    local session="$1"

    for pane in "${CLAUDE_PANES[@]}"; do
        local target="${session}:${pane}"

        # Check if pane exists
        tmux display-message -t "$target" -p "#{pane_id}" &>/dev/null || continue

        # Check process name
        local cmd=$(tmux display-message -t "$target" -p "#{pane_current_command}" 2>/dev/null || true)

        # Claude runs as node process
        if [[ "$cmd" == "node" ]]; then
            # Verify it's actually Claude by checking content
            local content=$(tmux capture-pane -t "$target" -p -S -10 2>/dev/null || true)
            # Look for Claude-specific indicators
            if [[ "$content" == *"tokens"* ]] || \
               [[ "$content" == *"Claude"* ]] || \
               [[ "$content" == *">"* && "$content" == *"ctrl+"* ]]; then
                echo "$pane"
                return 0
            fi
        fi
    done

    return 1
}

get_content_hash() {
    local content="$1"
    # Hash Claude's OUTPUT only, excluding:
    # - Input line (starts with > or contains user typing)
    # - Last 3 lines (usually prompt area)
    # - Dynamic counters (time, tokens)
    # - Spinner characters
    echo "$content" | \
        awk 'NR>3{print lines[NR%4]} {lines[NR%4]=$0}' | \
        grep -v '^>' | \
        grep -v '^ *$' | \
        grep -v 'INSERT' | \
        sed 's/[0-9]*s/Xs/g' | \
        sed 's/[0-9]*m/Xm/g' | \
        sed 's/[0-9.]*k tokens/Xk tokens/g' | \
        sed 's/[0-9]* tokens/X tokens/g' | \
        tr -d '⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏●○◐◑◒◓' | \
        tail -20 | \
        md5 2>/dev/null || echo "empty" | md5sum | cut -d' ' -f1
}

detect_idle_hint() {
    local content="$1"
    local last_lines=$(echo "$content" | tail -10)

    # Try to hint what type of idle based on patterns
    for hint in "${HINT_PATTERNS[@]}"; do
        local pattern="${hint%%:*}"
        local label="${hint##*:}"
        if echo "$last_lines" | grep -qE "$pattern"; then
            echo "$label"
            return
        fi
    done

    echo "idle"
}

detect_state() {
    local session="$1"
    local content="$2"
    local now=$(date +%s)

    local hash_file="${STATE_DIR}/${session}.hash"
    local time_file="${STATE_DIR}/${session}.time"

    local current_hash=$(get_content_hash "$content")
    local prev_hash=""
    local last_change=$now

    # Read previous hash
    if [[ -f "$hash_file" ]]; then
        prev_hash=$(cat "$hash_file")
    fi

    # Read last change time
    if [[ -f "$time_file" ]]; then
        last_change=$(cat "$time_file")
    fi

    # Check if content changed
    if [[ "$current_hash" != "$prev_hash" ]]; then
        # Content changed - reset timer
        echo "$current_hash" > "$hash_file"
        echo "$now" > "$time_file"
        echo "active"
        return
    fi

    # Content unchanged - check how long
    local idle_seconds=$((now - last_change))

    if [[ $idle_seconds -ge $IDLE_THRESHOLD ]]; then
        # Idle for too long - try to hint why
        detect_idle_hint "$content"
    else
        echo "active"
    fi
}

get_prompt_context() {
    local content="$1"
    # Get last non-empty line as context
    echo "$content" | grep -v '^[[:space:]]*$' | tail -3 | head -1 | cut -c1-80
}

get_idle_duration() {
    local session="$1"
    local time_file="${STATE_DIR}/${session}.time"
    local now=$(date +%s)
    local last_change=$(cat "$time_file" 2>/dev/null || echo "$now")
    local seconds=$((now - last_change))

    if [[ $seconds -ge 3600 ]]; then
        echo "$((seconds / 3600))h $((seconds % 3600 / 60))m"
    elif [[ $seconds -ge 60 ]]; then
        echo "$((seconds / 60))m $((seconds % 60))s"
    else
        echo "${seconds}s"
    fi
}

get_last_meaningful_lines() {
    local content="$1"
    local count="${2:-3}"

    echo "$content" | \
        sed 's/\x1b\[[0-9;]*m//g' | \
        grep -v '^[[:space:]]*$' | \
        grep -v '^[─═╔╗╚╝║┌┐└┘├┤]' | \
        tail -n "$count"
}

# ═══════════════════════════════════════════════════════════════
# STATE MANAGEMENT
# ═══════════════════════════════════════════════════════════════

write_state() {
    local session="$1"
    local pane="$2"
    local status="$3"
    local prompt="$4"
    local ts=$(date +%s)

    local state_file="${STATE_DIR}/${session}.state"
    cat > "$state_file" <<EOF
{
  "session": "$session",
  "pane": "$pane",
  "status": "$status",
  "prompt": "$prompt",
  "timestamp": $ts
}
EOF
}

read_state() {
    local session="$1"
    local state_file="${STATE_DIR}/${session}.state"

    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo '{"status": "unknown"}'
    fi
}

clear_state() {
    local session="$1"
    rm -f "${STATE_DIR}/${session}.state"
}

get_waiting_count() {
    local count=0
    for f in "${STATE_DIR}"/*.state; do
        [[ -f "$f" ]] || continue
        local status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' "$f" 2>/dev/null | \
            sed 's/.*"\([^"]*\)"$/\1/')
        # Count anything that's not "active" or "unknown"
        [[ "$status" != "active" && "$status" != "unknown" ]] && count=$((count + 1))
    done
    echo "$count"
}

# ═══════════════════════════════════════════════════════════════
# NOTIFICATIONS
# ═══════════════════════════════════════════════════════════════

notify_toast() {
    local title="$1"
    local message="$2"

    # macOS silent notification
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null || true
}

notify_tmux_status() {
    local count=$(get_waiting_count)

    if [[ $count -gt 0 ]]; then
        # Set tmux status (will be picked up by status-right)
        echo "$count" > "${MONITOR_DIR}/waiting_count"
    else
        rm -f "${MONITOR_DIR}/waiting_count"
    fi
}

send_notification() {
    local session="$1"
    local status="$2"
    local prompt="$3"
    local verbosity=$(get_verbosity)

    case "$verbosity" in
        silent)
            # Just update state files, no notification
            ;;
        minimal)
            notify_tmux_status
            ;;
        verbose)
            notify_tmux_status
            notify_toast "Claude: $session" "$status - $prompt"
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# DISPLAY
# ═══════════════════════════════════════════════════════════════

status_icon() {
    local status="$1"
    case "$status" in
        active)     echo -e "${C_GREEN}●${C_RESET}" ;;
        idle)       echo -e "${C_YELLOW}⏳${C_RESET}" ;;
        permission) echo -e "${C_YELLOW}🔐${C_RESET}" ;;
        question)   echo -e "${C_CYAN}?${C_RESET}" ;;
        confirm)    echo -e "${C_MAGENTA}!${C_RESET}" ;;
        *)          echo -e "${C_GRAY}○${C_RESET}" ;;
    esac
}

display_status() {
    local session="$1"
    local status="$2"
    local prompt="$3"
    local icon=$(status_icon "$status")

    printf " %s ${C_BOLD}%-20s${C_RESET} ${C_GRAY}%s${C_RESET}\n" \
        "$icon" "$session" "${prompt:0:50}"
}

display_header() {
    echo -e "\n${C_BOLD}Claude Monitor${C_RESET} $(date '+%H:%M')"
    echo -e "${C_GRAY}─────────────────────────────────────────────────${C_RESET}"
}

display_legend() {
    echo -e "\n${C_GRAY}Legend: ${C_GREEN}●${C_GRAY}=active ${C_YELLOW}⏳${C_GRAY}=idle ${C_CYAN}?${C_GRAY}=question ${C_MAGENTA}!${C_GRAY}=confirm${C_RESET}"
    echo -e "${C_GRAY}Idle threshold: ${IDLE_THRESHOLD}s of no output change${C_RESET}"
}

# ═══════════════════════════════════════════════════════════════
# VERBOSE DASHBOARD MODE
# ═══════════════════════════════════════════════════════════════

TERM_WIDTH=74

panel_draw_line() {
    local char="${1:-$BOX_H}"
    printf '%*s' "$TERM_WIDTH" '' | tr ' ' "$char"
}

panel_header() {
    local time=$(date '+%H:%M')
    echo -e "${C_CYAN}${BOX_TL}$(panel_draw_line)${BOX_TR}${C_RESET}"
    printf "${C_CYAN}${BOX_V}${C_RESET}  ${C_BOLD}${C_CYAN}◆ CLAUDE COMMAND CENTER${C_RESET}"
    printf "%*s" $((TERM_WIDTH - 26)) "$time"
    echo -e "  ${C_CYAN}${BOX_V}${C_RESET}"
    echo -e "${C_CYAN}${BOX_LT}$(panel_draw_line)${BOX_RT}${C_RESET}"
}

panel_section() {
    local icon="$1"
    local title="$2"
    local count="$3"
    local color="$4"
    echo -e "${C_CYAN}${BOX_V}${C_RESET}"
    echo -e "${C_CYAN}${BOX_V}${C_RESET}  ${color}${icon} ${title}${C_RESET} ${C_DIM}(${count})${C_RESET}"
}

panel_instance_card() {
    local num="$1"
    local target="$2"
    local status="$3"
    local duration="$4"
    local lines="$5"
    local color

    if [[ "$status" == "active" ]]; then
        color="${C_GREEN}"
    else
        color="${C_YELLOW}"
    fi

    # Card header
    local header="${num}. ${target}"
    local header_len=${#header}
    local duration_len=${#duration}
    local fill_len=$((TERM_WIDTH - header_len - duration_len - 8))
    local fill=$(printf '%*s' "$fill_len" '' | tr ' ' "$BOX_H")

    echo -e "${C_CYAN}${BOX_V}${C_RESET}  ${color}${BOX_TL}${BOX_H} ${header} ${fill} ${duration} ${BOX_H}${BOX_TR}${C_RESET}"

    # Output lines
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local display_line="${line:0:$((TERM_WIDTH - 8))}"
        printf "${C_CYAN}${BOX_V}${C_RESET}  ${color}${BOX_V}${C_RESET} ${C_DIM}%-$((TERM_WIDTH - 6))s${C_RESET} ${color}${BOX_V}${C_RESET}\n" "$display_line"
    done <<< "$lines"

    # Card footer
    echo -e "${C_CYAN}${BOX_V}${C_RESET}  ${color}${BOX_BL}$(printf '%*s' $((TERM_WIDTH - 4)) '' | tr ' ' "$BOX_H")${BOX_BR}${C_RESET}"
}

panel_footer() {
    local waiting="$1"
    local active="$2"
    echo -e "${C_CYAN}${BOX_V}${C_RESET}"
    echo -e "${C_CYAN}${BOX_LT}$(panel_draw_line)${BOX_RT}${C_RESET}"
    printf "${C_CYAN}${BOX_V}${C_RESET}  ${C_YELLOW}⏳ ${waiting} waiting${C_RESET}   ${C_GREEN}● ${active} active${C_RESET}"
    printf "%*s" $((TERM_WIDTH - 48)) "[1-9] jump  [r] refresh  [C-a B] back  [q] quit"
    echo -e "  ${C_CYAN}${BOX_V}${C_RESET}"
    echo -e "${C_CYAN}${BOX_BL}$(panel_draw_line)${BOX_BR}${C_RESET}"
}

panel_loop() {
    tput civis 2>/dev/null
    trap '
        log "panel_loop: trap triggered, cleaning up"
        stty sane 2>/dev/null
        tput cnorm 2>/dev/null
        rm -f /tmp/claude-monitor-$$-* 2>/dev/null
        exit
    ' INT TERM EXIT

    log "panel_loop: started (PID: $$)"
    clear

    while true; do
        tput home 2>/dev/null

        # Use temp files for reliable data storage (bash 3.2 compatible)
        local tmp_prefix="/tmp/claude-monitor-$$"
        rm -f ${tmp_prefix}-* 2>/dev/null

        local sessions=$(get_tmux_sessions)
        local waiting_count=0 active_count=0
        local instance_num=0

        # Collect all instances
        for session in $sessions; do
            local pane=$(find_claude_pane "$session")
            [[ -z "$pane" ]] && continue

            local target="${session}:${pane}"
            local content=$(get_pane_content "$target")
            local status=$(detect_state "$session" "$content")
            local duration=$(get_idle_duration "$session")
            local lines=$(get_last_meaningful_lines "$content" 2)

            # Store in temp files
            if [[ "$status" == "active" ]]; then
                echo "${target}|${status}|${duration}" >> "${tmp_prefix}-active"
                echo "$lines" > "${tmp_prefix}-active-lines-${active_count}"
                active_count=$((active_count + 1))
            else
                echo "${target}|${status}|${duration}" >> "${tmp_prefix}-waiting"
                echo "$lines" > "${tmp_prefix}-waiting-lines-${waiting_count}"
                waiting_count=$((waiting_count + 1))
            fi

            write_state "$session" "$pane" "$status" "$(echo "$lines" | head -1)"
        done

        # Build ordered target list for number shortcuts
        local all_targets=""
        [[ -f "${tmp_prefix}-waiting" ]] && all_targets=$(cut -d'|' -f1 "${tmp_prefix}-waiting" | tr '\n' '|')
        [[ -f "${tmp_prefix}-active" ]] && all_targets="${all_targets}$(cut -d'|' -f1 "${tmp_prefix}-active" | tr '\n' '|')"
        echo "$all_targets" > "${tmp_prefix}-all"

        # Display
        panel_header

        # Waiting section
        if [[ $waiting_count -gt 0 ]]; then
            panel_section "⏳" "AWAITING INPUT" "$waiting_count" "${C_YELLOW}"
            local num=1
            while IFS='|' read -r target status duration; do
                [[ -z "$target" ]] && continue
                local lines=$(cat "${tmp_prefix}-waiting-lines-$((num - 1))" 2>/dev/null)
                panel_instance_card "$num" "$target" "$status" "$duration" "$lines"
                num=$((num + 1))
            done < "${tmp_prefix}-waiting"
        fi

        # Active section
        if [[ $active_count -gt 0 ]]; then
            panel_section "●" "ACTIVE" "$active_count" "${C_GREEN}"
            local num=$((waiting_count + 1))
            local idx=0
            while IFS='|' read -r target status duration; do
                [[ -z "$target" ]] && continue
                local lines=$(cat "${tmp_prefix}-active-lines-${idx}" 2>/dev/null)
                panel_instance_card "$num" "$target" "$status" "$duration" "$lines"
                num=$((num + 1))
                idx=$((idx + 1))
            done < "${tmp_prefix}-active"
        fi

        if [[ $((waiting_count + active_count)) -eq 0 ]]; then
            echo -e "${C_CYAN}${BOX_V}${C_RESET}"
            echo -e "${C_CYAN}${BOX_V}${C_RESET}  ${C_DIM}No Claude instances detected${C_RESET}"
        fi

        panel_footer "$waiting_count" "$active_count"

        # Clear any leftover lines from previous render
        for i in 1 2 3 4 5; do
            tput el 2>/dev/null
            echo ""
        done

        notify_tmux_status

        # Non-blocking key check
        if read -t "$POLL_INTERVAL" -n 1 key 2>/dev/null; then
            case "$key" in
                q|Q)
                    log "panel_loop: quit requested"
                    tput cnorm 2>/dev/null
                    rm -f ${tmp_prefix}-* 2>/dev/null
                    exit 0
                    ;;
                r|R)
                    # Force full redraw to fix visual glitches
                    clear
                    ;;
                [1-9])
                    local idx=$((key - 1))
                    local all=$(cat "${tmp_prefix}-all" 2>/dev/null)
                    local goto_target=$(echo "$all" | cut -d'|' -f$key)
                    log "panel_loop: key=$key goto_target=$goto_target"
                    if [[ -n "$goto_target" && "$goto_target" != "|" && "$goto_target" != "" ]]; then
                        # Save current pane location for "back" command
                        local current_pane=$(tmux display-message -p '#S:#I.#P')
                        echo "$current_pane" > "${MONITOR_DIR}/panel_pane"
                        log "panel_loop: jumping from $current_pane to $goto_target"

                        # Parse target (format: session:window.pane)
                        local target_session="${goto_target%%:*}"
                        local target_wp="${goto_target#*:}"

                        # Switch to target - dashboard keeps running in this pane
                        tmux switch-client -t "${target_session}:${target_wp}" 2>/dev/null || {
                            log "panel_loop: direct switch failed, trying fallback"
                            tmux switch-client -t "$target_session" 2>/dev/null || true
                            tmux select-window -t "${target_session}:${target_wp%%.*}" 2>/dev/null || true
                            tmux select-pane -t "${target_session}:${target_wp}" 2>/dev/null || true
                        }
                        log "panel_loop: switch complete, continuing loop"
                        # Don't exit - dashboard continues running, user can switch back
                    fi
                    ;;
            esac
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
# MAIN LOOP
# ═══════════════════════════════════════════════════════════════

poll_once() {
    local sessions=$(get_tmux_sessions)
    local found_any=0

    for session in $sessions; do
        # Find Claude pane in this session
        local pane=$(find_claude_pane "$session")
        if [[ -z "$pane" ]]; then
            clear_state "$session"
            continue
        fi

        found_any=1
        local target="${session}:${pane}"

        local content=$(get_pane_content "$target")
        local status=$(detect_state "$session" "$content")
        local prompt=$(get_prompt_context "$content")

        # Get previous state
        local prev_status=$(grep -o '"status"[[:space:]]*:[[:space:]]*"[^"]*"' \
            "${STATE_DIR}/${session}.state" 2>/dev/null | \
            sed 's/.*"\([^"]*\)"$/\1/' || echo "unknown")

        # Write new state
        write_state "$session" "$pane" "$status" "$prompt"

        # Notify on state change (from active to idle/waiting)
        if [[ "$prev_status" == "active" && "$status" != "active" ]]; then
            send_notification "$session" "$status" "$prompt"
            log "State change: $session:$pane $prev_status -> $status"
        fi
    done

    # Update tmux status
    notify_tmux_status

    return $found_any
}

foreground_loop() {
    # Hide cursor
    tput civis 2>/dev/null

    # Restore TTY on exit
    trap '
        stty sane 2>/dev/null
        tput cnorm 2>/dev/null
        exit
    ' INT TERM EXIT

    # Initial clear
    clear

    while true; do
        # Move cursor to top (no clear = no blink)
        tput home 2>/dev/null

        display_header

        local sessions=$(get_tmux_sessions)
        local found=0
        local line_count=0

        for session in $sessions; do
            local pane=$(find_claude_pane "$session")
            if [[ -n "$pane" ]]; then
                found=1
                local target="${session}:${pane}"
                local content=$(get_pane_content "$target")
                local status=$(detect_state "$session" "$content")
                local prompt=$(get_prompt_context "$content")

                write_state "$session" "$pane" "$status" "$prompt"
                display_status "$session:$pane" "$status" "$prompt"
                line_count=$((line_count + 1))
            fi
        done

        if [[ $found -eq 0 ]]; then
            echo -e " ${C_GRAY}No Claude instances detected${C_RESET}"
            line_count=1
        fi

        display_legend

        # Clear any leftover lines from previous longer output
        tput el 2>/dev/null  # Clear to end of line

        notify_tmux_status

        sleep "$POLL_INTERVAL"
    done
}

daemon_loop() {
    log "Daemon started (PID: $$)"

    while true; do
        poll_once || true
        sleep "$POLL_INTERVAL"
    done
}

# ═══════════════════════════════════════════════════════════════
# COMMANDS
# ═══════════════════════════════════════════════════════════════

cmd_start() {
    ensure_dirs

    if [[ -f "$PID_FILE" ]] && ps -p "$(cat "$PID_FILE")" &>/dev/null; then
        echo "Monitor already running (PID: $(cat "$PID_FILE"))"
        return 0
    fi

    # Start daemon in background
    nohup "$0" _daemon >> "$LOG_FILE" 2>&1 &
    local pid=$!
    echo "$pid" > "$PID_FILE"

    echo "Monitor started (PID: $pid)"
    echo "Logs: $LOG_FILE"
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

    # Kill ALL orphaned monitor processes (except self)
    local self_pid=$$
    local orphans=$(pgrep -f 'claude-monitor-daemon' 2>/dev/null | grep -v "^${self_pid}$" || true)
    if [[ -n "$orphans" ]]; then
        echo "$orphans" | while read pid; do
            kill "$pid" 2>/dev/null && killed=$((killed + 1))
        done
    fi

    # Clean up temp and state files
    rm -f /tmp/claude-monitor-* 2>/dev/null || true
    rm -f "${STATE_DIR}"/*.state 2>/dev/null || true
    rm -f "${MONITOR_DIR}/waiting_count" 2>/dev/null || true
    rm -f "${MONITOR_DIR}/panel_pane" 2>/dev/null || true

    if [[ $killed -gt 0 ]]; then
        echo "Monitor stopped (killed $killed process(es))"
    else
        echo "Monitor not running"
    fi
}

cmd_restart() {
    cmd_stop
    sleep 0.5
    cmd_start
}

cmd_back() {
    local panel_pane="${MONITOR_DIR}/panel_pane"
    if [[ -f "$panel_pane" ]]; then
        local target=$(cat "$panel_pane")
        # Switch directly to the pane where monitor is still running
        tmux switch-client -t "$target" 2>/dev/null || {
            local target_session="${target%%:*}"
            local target_wp="${target#*:}"
            tmux switch-client -t "$target_session" 2>/dev/null || true
            tmux select-window -t "${target_session}:${target_wp%%.*}" 2>/dev/null || true
            tmux select-pane -t "$target" 2>/dev/null || true
        }
        # Dashboard is still running - no restart needed
    else
        echo "No monitor session to return to. Start with: claude-util mon -fv"
        exit 1
    fi
}

cmd_status() {
    if [[ -f "$PID_FILE" ]] && ps -p "$(cat "$PID_FILE")" &>/dev/null; then
        echo -e "Monitor: ${C_GREEN}RUNNING${C_RESET} (PID: $(cat "$PID_FILE"))"
    else
        echo -e "Monitor: ${C_RED}STOPPED${C_RESET}"
    fi

    echo -e "Verbosity: ${C_CYAN}$(get_verbosity)${C_RESET}"
    echo -e "Waiting: ${C_YELLOW}$(get_waiting_count)${C_RESET}"
}

cmd_list() {
    ensure_dirs

    echo -e "${C_BOLD}Claude Instances${C_RESET}"
    echo -e "${C_GRAY}────────────────────────────────────────${C_RESET}"

    local sessions=$(get_tmux_sessions)
    local found=0

    for session in $sessions; do
        local pane=$(find_claude_pane "$session")
        if [[ -n "$pane" ]]; then
            found=1
            local target="${session}:${pane}"
            local content=$(get_pane_content "$target")
            local status=$(detect_state "$session" "$content")
            local prompt=$(get_prompt_context "$content")
            display_status "$session:$pane" "$status" "$prompt"
        fi
    done

    if [[ $found -eq 0 ]]; then
        echo -e " ${C_GRAY}No Claude instances detected${C_RESET}"
    fi

    display_legend
}

cmd_goto() {
    local input="$1"

    if [[ -z "$input" ]]; then
        echo "Usage: claude-monitor-daemon goto <session>[:<pane>]"
        echo "Example: goto myproject"
        echo "         goto myproject:1.0"
        return 1
    fi

    local session pane

    # Check if input includes pane (session:pane format)
    if [[ "$input" == *":"* ]]; then
        session="${input%%:*}"
        pane="${input#*:}"
    else
        session="$input"
        # Look up pane from state file or find it
        pane=$(grep -o '"pane"[[:space:]]*:[[:space:]]*"[^"]*"' \
            "${STATE_DIR}/${session}.state" 2>/dev/null | \
            sed 's/.*"\([^"]*\)"$/\1/')

        # If no state, try to find Claude pane
        if [[ -z "$pane" ]]; then
            pane=$(find_claude_pane "$session")
        fi

        # Default to 0.0
        if [[ -z "$pane" ]]; then
            pane="0.0"
        fi
    fi

    # Check if session exists
    if ! tmux has-session -t "$session" 2>/dev/null; then
        echo "Session not found: $session"
        return 1
    fi

    local target="${session}:${pane}"

    # Switch to session and pane
    tmux switch-client -t "$target" 2>/dev/null || \
        tmux select-window -t "${session}:${pane%%.*}" && \
        tmux select-pane -t "$target"

    echo "Switched to: $target"
}

cmd_foreground() {
    ensure_dirs
    foreground_loop
}

cmd_foreground_verbose() {
    ensure_dirs
    panel_loop
}

cmd_attach() {
    # Same as foreground but doesn't start daemon
    ensure_dirs
    foreground_loop
}

cmd_logs() {
    local lines="${1:-50}"
    if [[ -f "$LOG_FILE" ]]; then
        tail -n "$lines" "$LOG_FILE"
    else
        echo "No logs yet"
    fi
}

cmd_verbosity() {
    local level="$1"
    case "$level" in
        silent|minimal|verbose)
            set_verbosity "$level"
            ;;
        "")
            echo "Current: $(get_verbosity)"
            echo "Options: silent | minimal | verbose"
            ;;
        *)
            echo "Invalid verbosity: $level"
            echo "Options: silent | minimal | verbose"
            return 1
            ;;
    esac
}

cmd_debug() {
    local toggle="$1"
    ensure_dirs
    
    case "$toggle" in
        on)
            # Enable debug logging
            if [[ -f "$CONFIG_FILE" ]]; then
                # Update existing config
                if grep -q '"debug"' "$CONFIG_FILE"; then
                    sed -i '' 's/"debug"[[:space:]]*:[[:space:]]*false/"debug": true/' "$CONFIG_FILE"
                else
                    # Add debug to config
                    sed -i '' 's/}$/, "debug": true}/' "$CONFIG_FILE"
                fi
            else
                echo '{"debug": true}' > "$CONFIG_FILE"
            fi
            echo "Debug logging: ON"
            echo "Logs: $LOG_FILE"
            ;;
        off)
            # Disable debug logging and clean up
            if [[ -f "$CONFIG_FILE" ]]; then
                sed -i '' 's/"debug"[[:space:]]*:[[:space:]]*true/"debug": false/' "$CONFIG_FILE"
            fi
            rm -f "$LOG_FILE" 2>/dev/null
            echo "Debug logging: OFF (log file cleaned)"
            ;;
        "")
            echo "Debug: $(get_debug)"
            [[ -f "$LOG_FILE" ]] && echo "Log size: $(wc -c < "$LOG_FILE" | tr -d ' ') bytes"
            ;;
        *)
            echo "Usage: debug [on|off]"
            return 1
            ;;
    esac
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        start)      cmd_start ;;
        stop)       cmd_stop ;;
        restart)    cmd_restart ;;
        back)       cmd_back ;;
        status)     cmd_status ;;
        list)       cmd_list ;;
        goto)       cmd_goto "$@" ;;
        foreground|-f) cmd_foreground ;;
        -fv) cmd_foreground_verbose ;;
        attach)     cmd_attach ;;
        logs)       cmd_logs "$@" ;;
        verbosity)  cmd_verbosity "$@" ;;
        debug)      cmd_debug "$@" ;;
        _daemon)    daemon_loop ;;  # Internal: run daemon loop
        help|--help|-h)
            cat <<EOF
claude-monitor-daemon - Monitor Claude instances across tmux sessions

Usage: claude-monitor-daemon <command> [args]

Commands:
  start           Start the monitor daemon in background
  stop            Stop the monitor daemon
  restart         Stop and start the monitor daemon
  back            Switch back to the running monitor dashboard
  status          Show monitor status
  list            List all Claude instances and their state
  goto <session>  Jump to a specific session's Claude pane
  foreground, -f  Run monitor in foreground with live display
  -fv             Verbose dashboard mode (with output preview)
  attach          Attach to see live status (alias for foreground)
  logs [n]        Show last n lines of log (default: 50)
  verbosity [lvl] Get/set notification level (silent|minimal|verbose)
  debug [on|off]  Toggle debug logging (off cleans up log file)

Notification Levels:
  silent   - State tracking only, no notifications
  minimal  - Update tmux status line with waiting count
  verbose  - macOS notifications (silent) + tmux status

State Icons:
  ● active   - Claude is working (output changing)
  ⏳ idle     - No output change for 30s (needs attention)
  🔐 permission - Hint: likely a permission prompt
  ? question - Hint: likely asking a question
  ! confirm  - Hint: likely needs confirmation

EOF
            ;;
        *)
            echo "Unknown command: $cmd"
            echo "Run 'claude-monitor-daemon help' for usage"
            return 1
            ;;
    esac
}

main "$@"
