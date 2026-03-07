#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default keybinding: prefix + /
KEY=$(tmux show-option -gqv @grep-key 2>/dev/null)
KEY="${KEY:-/}"

tmux bind-key "$KEY" display-popup -E -w 90% -h 80% "${CURRENT_DIR}/scripts/tmux-grep.sh"
