#!/bin/bash
# Shell Snapshot Cleanup Utility
# Manages corrupted shell snapshots in ~/.claude/shell-snapshots/

SNAPSHOT_DIR="$HOME/.claude/shell-snapshots"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Command 1: Delete all .sh files
delete_all() {
    echo -e "${YELLOW}Deleting all .sh files in $SNAPSHOT_DIR${NC}"

    if [ ! -d "$SNAPSHOT_DIR" ]; then
        echo -e "${RED}Directory not found: $SNAPSHOT_DIR${NC}"
        return 1
    fi

    local count=$(find "$SNAPSHOT_DIR" -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')

    if [ "$count" -eq 0 ]; then
        echo -e "${GREEN}No .sh files found${NC}"
        return 0
    fi

    find "$SNAPSHOT_DIR" -name "*.sh" -type f -delete
    echo -e "${GREEN}Deleted $count file(s)${NC}"
}

# Command 2: Fix line 4903 trailing }
fix_line_4903() {
    local target_file="$1"

    if [ -n "$target_file" ]; then
        # Single file mode
        if [ ! -f "$target_file" ]; then
            echo -e "${RED}File not found: $target_file${NC}"
            return 1
        fi
        fix_single_file "$target_file"
    else
        # All files mode
        echo -e "${YELLOW}Checking and fixing line 4903 in all .sh files${NC}"

        if [ ! -d "$SNAPSHOT_DIR" ]; then
            echo -e "${RED}Directory not found: $SNAPSHOT_DIR${NC}"
            return 1
        fi

        local fixed_count=0
        local total_count=0

        while IFS= read -r file; do
            total_count=$((total_count + 1))
            if fix_single_file "$file" "quiet"; then
                fixed_count=$((fixed_count + 1))
            fi
        done < <(find "$SNAPSHOT_DIR" -name "*.sh" -type f)

        echo -e "${GREEN}Processed $total_count file(s), fixed $fixed_count${NC}"
    fi
}

# Helper: Fix a single file
fix_single_file() {
    local file="$1"
    local quiet="${2:-}"
    local fixed=0

    [ "$quiet" != "quiet" ] && echo "  Checking $(basename "$file")"

    # Pattern 1: Fix rule() function corruption
    # The bug creates: ─"}\n} (extra closing brace on next line)
    if grep -q '─"}' "$file" 2>/dev/null; then
        sed -i.bak -e '/─"}$/{ n; /^}$/d; }' "$file"
        rm -f "${file}.bak"
        fixed=1
        [ "$quiet" != "quiet" ] && echo "    Fixed: rule() brace pattern"
    fi

    # Pattern 2: Scan lines 4800-5200 for standalone } or )
    local line_num
    for line_num in $(sed -n '4800,5200{=;p}' "$file" 2>/dev/null | sed 'N;s/\n/ /' | grep -E '^[0-9]+ [[:space:]]*[})][[:space:]]*$' | cut -d' ' -f1); do
        sed -i.bak "${line_num}d" "$file"
        rm -f "${file}.bak"
        fixed=1
        [ "$quiet" != "quiet" ] && echo "    Fixed: standalone brace at line $line_num"
    done

    if [ $fixed -eq 1 ]; then
        [ "$quiet" != "quiet" ] && echo -e "${GREEN}✓ Fixed: $(basename "$file")${NC}"
        return 0
    fi

    [ "$quiet" != "quiet" ] && echo -e "${YELLOW}  No corruption found${NC}"
    return 1
}

# Command 3: Status - show count and creation dates
status() {
    echo -e "${YELLOW}Shell Snapshot Status${NC}"
    echo "Directory: $SNAPSHOT_DIR"
    echo ""

    if [ ! -d "$SNAPSHOT_DIR" ]; then
        echo -e "${RED}Directory not found${NC}"
        return 1
    fi

    local count=$(find "$SNAPSHOT_DIR" -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo -e "${GREEN}Total .sh files: $count${NC}"
    echo ""

    if [ "$count" -eq 0 ]; then
        echo "No files found"
        return 0
    fi

    echo "Files (oldest to newest):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # macOS compatible ls with birth time, sort by creation date ascending
    find "$SNAPSHOT_DIR" -name "*.sh" -type f -exec stat -f "%B %N" {} \; 2>/dev/null | \
        sort -n | \
        while read timestamp filepath; do
            filename=$(basename "$filepath")
            # Convert timestamp to readable date
            date_str=$(date -r "$timestamp" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || echo "unknown")

            # Check if line 4903 has problematic }
            if sed -n '4903p' "$filepath" 2>/dev/null | grep -qx '[[:space:]]*}[[:space:]]*'; then
                echo -e "${RED}✗${NC} $date_str - $filename ${RED}(corrupted line 4903)${NC}"
            else
                echo -e "${GREEN}✓${NC} $date_str - $filename"
            fi
        done
}

# Main command dispatcher
case "${1:-status}" in
    delete|d)
        delete_all
        ;;
    fix|f)
        fix_line_4903
        ;;
    status|s)
        status
        ;;
    help|h|--help|-h)
        echo "Shell Snapshot Cleanup Utility"
        echo ""
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  delete, d    Delete all .sh files in shell-snapshots"
        echo "  fix, f       Fix corrupted line 4903 in all .sh files"
        echo "  status, s    Show file count and creation dates (default)"
        echo "  help, h      Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0 status    # Show current status"
        echo "  $0 fix       # Fix corrupted files"
        echo "  $0 delete    # Delete all snapshot files"
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
