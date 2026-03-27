#!/usr/bin/env bash
set -euo pipefail

# dev-popup: find the dev server pane for the current working directory
# and show its recent output in a tmux popup via less.

# Dev server processes — highest priority match
DEV_SERVERS="^(node|pnpm|npm|vite|next|tsx|ts-node|bun|deno)$"
# Non-dev tools to skip (editors, TUIs, agents)
SKIP="^(zsh|bash|fish|sh|dash|nvim|vim|vi|claude|lazygit|htop|less|man|git)$"

# Get the invoking pane's working directory and ID
CALLER_PANE="$1"
CWD=$(tmux display-message -t "$CALLER_PANE" -p '#{pane_current_path}')
PROJECT=$(basename "$CWD")

# Find dev server pane: same directory tree, prefer dev server processes
# Two passes: first look for known dev servers, then any non-skipped process
TARGET=""
FALLBACK=""
while IFS=$'\t' read -r pane_id pane_path pane_cmd; do
    [[ "$pane_id" == "$CALLER_PANE" ]] && continue
    # Match CWD or any subdirectory of CWD
    [[ "$pane_path" != "$CWD" && "$pane_path" != "$CWD/"* ]] && continue

    if [[ "$pane_cmd" =~ $DEV_SERVERS ]]; then
        TARGET="$pane_id"
        break
    elif [[ ! "$pane_cmd" =~ $SKIP && -z "$FALLBACK" ]]; then
        FALLBACK="$pane_id"
    fi
done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_path}	#{pane_current_command}')

TARGET="${TARGET:-$FALLBACK}"

if [[ -z "$TARGET" ]]; then
    echo "No dev server found for: $PROJECT"
    echo ""
    echo "Looking for a non-shell process in: $CWD"
    echo ""
    echo "Running panes in this directory:"
    while IFS=$'\t' read -r pane_id pane_path pane_cmd; do
        [[ "$pane_path" == "$CWD" ]] && echo "  $pane_id  $pane_cmd"
    done < <(tmux list-panes -a -F '#{pane_id}	#{pane_current_path}	#{pane_current_command}')
    echo ""
    read -n 1 -s -r -p "Press any key to close..."
    exit 0
fi

# Capture the pane's scrollback with ANSI colors and show in less
# -S 500: capture up to 500 lines of scrollback history
# -e: preserve escape sequences (colors)
# -p: print to stdout
tmux capture-pane -t "$TARGET" -e -p -S -500 | less -R +G
