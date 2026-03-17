#!/usr/bin/env bash
# Kill a tmux session or window with confirmation.
# Called from fzf execute() — runs in a visible sub-shell.
# Usage: kill-target.sh <selected-line>

set -euo pipefail

SELECTION="$*"
[ -z "$SELECTION" ] && exit 0

MODE=$(echo "$SELECTION" | cut -f1)
TARGET=$(echo "$SELECTION" | cut -f2)
DISPLAY=$(echo "$SELECTION" | cut -f3-)

case "$MODE" in
    S)
        current=$(tmux display-message -p '#{session_name}' 2>/dev/null || true)
        if [ "$TARGET" = "$current" ]; then
            exit 0
        fi
        tmux kill-session -t "$TARGET" 2>/dev/null || true
        ;;
    W)
        tmux kill-window -t "$TARGET" 2>/dev/null || true
        ;;
    *)
        exit 0
        ;;
esac
