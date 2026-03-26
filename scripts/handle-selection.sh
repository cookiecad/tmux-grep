#!/usr/bin/env bash
# Dispatches fzf selection based on mode tag (field 1).
# Usage: handle-selection.sh <query> <selected-line>
# Query is passed for search-forward highlighting in grep mode.

set -euo pipefail

QUERY="${1:-}"
shift
SELECTION="$*"

[ -z "$SELECTION" ] && exit 0

MODE=$(echo "$SELECTION" | cut -f1)
FIELD2=$(echo "$SELECTION" | cut -f2)

case "$MODE" in
    S)
        # Session: switch to it
        tmux switch-client -t "$FIELD2"
        ;;
    W)
        # Window: select window and switch to session
        # FIELD2 = session:window_index
        session="${FIELD2%%:*}"
        tmux select-window -t "$FIELD2"
        tmux switch-client -t "$session"
        ;;
    H|E)
        # Group header or expand marker: switch to that window/pane
        session="${FIELD2%%:*}"
        window_target="${FIELD2%.*}"
        tmux select-window -t "$window_target"
        tmux select-pane -t "$FIELD2"
        tmux switch-client -t "$session"
        ;;
    G)
        # Grep: navigate to exact line in pane
        target="${FIELD2%|*}"
        line_num="${FIELD2#*|}"

        # Switch to the target session/window/pane
        session="${target%%:*}"
        tmux select-window -t "${target%.*}"
        tmux select-pane -t "$target"
        tmux switch-client -t "$session"

        # Enter copy-mode and position at the match line
        tmux copy-mode -t "$target"
        tmux send-keys -t "$target" -X history-top
        if [ "$line_num" -gt 1 ]; then
            tmux send-keys -t "$target" -X -N "$((line_num - 2))" cursor-down
        fi

        # Search forward to highlight and enable n/N navigation
        if [ -n "$QUERY" ]; then
            tmux send-keys -t "$target" -X search-forward "$QUERY"
        fi
        ;;
esac
