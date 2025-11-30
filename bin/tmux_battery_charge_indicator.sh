#!/bin/bash
# Simple battery indicator for tmux status bar
# Shows: ♥♥♥♥♥♥♥♥♡♡ (filled hearts for charge level)

HEART_FULL='♥'
HEART_EMPTY='♡'

# Get battery percentage
if [[ $(uname) == 'Darwin' ]]; then
    # macOS - use pmset (simple and reliable)
    percent=$(pmset -g batt | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
else
    # Linux
    percent=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
fi

# Exit silently if no battery (desktop)
[[ -z "$percent" ]] && exit 0

# Calculate hearts (10 total)
filled=$((percent / 10))
empty=$((10 - filled))

# Color based on level
if [[ $percent -le 20 ]]; then
    color="red"
elif [[ $percent -le 50 ]]; then
    color="yellow"
else
    color="green"
fi

# Output
echo -n "#[fg=$color]"
for ((i=0; i<filled; i++)); do echo -n "$HEART_FULL"; done
echo -n "#[fg=white]"
for ((i=0; i<empty; i++)); do echo -n "$HEART_EMPTY"; done
