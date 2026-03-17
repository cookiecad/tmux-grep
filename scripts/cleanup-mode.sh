#!/usr/bin/env bash
# Cleanup triage: multi-select idle panes to kill.
# Launched from the main switcher via ctrl-d, or directly.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Preview: show pane content
PREVIEW='
target=$(echo {} | cut -f2)
tmux capture-pane -pJ -t "$target" 2>/dev/null || echo "No preview"
'

# Generate candidate list
DATA=$(bash "$SCRIPT_DIR/cleanup.sh" 2>/dev/null)

if [ -z "$DATA" ]; then
    echo "No idle panes found — nothing to clean up."
    sleep 1.5
    exit 0
fi

COUNT=$(echo "$DATA" | wc -l)
echo "Found $COUNT idle pane(s). Use tab to mark, enter to kill marked."
echo ""

# Multi-select fzf
SELECTED=$(echo "$DATA" | fzf \
    --ansi \
    --multi \
    --no-sort \
    --layout=reverse \
    --delimiter=$'\t' \
    --with-nth=3.. \
    --header="Cleanup: tab=mark/unmark  enter=kill marked  esc=cancel  ctrl-a=select all" \
    --prompt="Cleanup> " \
    --preview="$PREVIEW" \
    --preview-window='right:50%:wrap' \
    --bind="ctrl-a:select-all" \
    --bind="ctrl-n:deselect-all" \
) || exit 0

[ -z "$SELECTED" ] && exit 0

# Count and confirm
KILL_COUNT=$(echo "$SELECTED" | wc -l)

echo ""
echo "About to kill $KILL_COUNT pane(s):"
echo "$SELECTED" | while IFS=$'\t' read -r tag target display; do
    echo "  $target"
done
echo ""
printf "Proceed? [y/N] "
read -r -n1 answer
echo

if [[ ! "$answer" =~ ^[yY]$ ]]; then
    echo "Cancelled."
    sleep 0.5
    exit 0
fi

# Kill selected panes
KILLED=0
FAILED=0
echo "$SELECTED" | while IFS=$'\t' read -r tag target display; do
    # target is session:window.pane
    if tmux kill-pane -t "$target" 2>/dev/null; then
        echo "  Killed $target"
    else
        echo "  Failed: $target"
    fi
done

echo ""
echo "Done."
sleep 1
