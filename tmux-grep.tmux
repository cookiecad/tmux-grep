#!/usr/bin/env bash
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make scripts executable
chmod +x "$CURRENT_DIR"/scripts/*.sh

# Session switcher: prefix + S (overrides tmux-claude-status binding)
SWITCHER_KEY=$(tmux show-option -gqv @grep-switcher-key 2>/dev/null)
SWITCHER_KEY="${SWITCHER_KEY:-S}"
tmux bind-key "$SWITCHER_KEY" display-popup -E -w 90% -h 80% \
    "${CURRENT_DIR}/scripts/tmux-grep.sh --mode sessions"

# Pane content search: prefix + /
SEARCH_KEY=$(tmux show-option -gqv @grep-key 2>/dev/null)
SEARCH_KEY="${SEARCH_KEY:-/}"
tmux bind-key "$SEARCH_KEY" display-popup -E -w 90% -h 80% \
    "${CURRENT_DIR}/scripts/tmux-grep.sh --mode search"
