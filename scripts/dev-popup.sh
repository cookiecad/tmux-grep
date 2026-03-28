#!/usr/bin/env bash
set -euo pipefail

# dev-popup: find the pane running "pnpm dev" for the current project
# and show its recent output in a tmux popup via less.
#
# Detection: checks each pane's child processes for "pnpm dev" in the
# command line. Matches panes in the same directory or subdirectories.

CALLER_PANE="$1"
CWD=$(tmux display-message -t "$CALLER_PANE" -p '#{pane_current_path}')
PROJECT=$(basename "$CWD")

# Check if a pane's process tree contains "pnpm dev"
has_pnpm_dev() {
    local pane_pid
    pane_pid=$(tmux display-message -t "$1" -p '#{pane_pid}')
    # Check direct children for pnpm dev in their cmdline
    for child in $(pgrep -P "$pane_pid" 2>/dev/null); do
        if tr '\0' ' ' < "/proc/$child/cmdline" 2>/dev/null | grep -q "pnpm dev"; then
            return 0
        fi
    done
    return 1
}

TARGET=""
while IFS=$'\t' read -r pane_id pane_path; do
    [[ "$pane_id" == "$CALLER_PANE" ]] && continue
    [[ "$pane_path" != "$CWD" && "$pane_path" != "$CWD/"* ]] && continue

    if has_pnpm_dev "$pane_id"; then
        TARGET="$pane_id"
        break
    fi
done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_path}')

if [[ -z "$TARGET" ]]; then
    echo "No pnpm dev found for: $PROJECT ($CWD)"
    echo ""
    read -n 1 -s -r -p "Press any key to close..."
    exit 0
fi

# Copy-mode doesn't work in tmux popups (confirmed tmux limitation).
# Open in editor for full scroll/select/copy support.
TMPFILE=$(mktemp /tmp/dev-popup.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT
tmux capture-pane -t "$TARGET" -p -S -500 > "$TMPFILE"
"${EDITOR:-vim}" -R +$ "$TMPFILE"
