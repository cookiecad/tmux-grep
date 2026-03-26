#!/usr/bin/env bash
# Builds pane content search index. Captures scrollback to files and writes a manifest.
# No stdout — filter.sh handles display.
# Usage: search.sh --index-dir DIR

set -euo pipefail

INDEX_DIR=""
for arg in "$@"; do
    case "$arg" in
        --index-dir) shift; INDEX_DIR="${1:-}" ;;
    esac
    shift 2>/dev/null || true
done

if [ -z "$INDEX_DIR" ]; then
    echo "search.sh: --index-dir required" >&2
    exit 1
fi

mkdir -p "$INDEX_DIR"

# Configurable via tmux options
DEPTH=$(tmux show-option -gqv @grep-depth 2>/dev/null || true)
DEPTH="${DEPTH:--5000}"

# Clear previous manifest and expanded state
> "$INDEX_DIR/.manifest"
> "$INDEX_DIR/.expanded"

# Capture all panes' scrollback and build manifest
while IFS=$'\t' read -r target window_name pane_cmd; do
    safe="${target//[:.]/_}"
    outfile="${INDEX_DIR}/pane_${safe}"

    tmux capture-pane -p -S "$DEPTH" -t "$target" > "$outfile" 2>/dev/null || continue

    total=$(wc -l < "$outfile")
    [ "$total" -eq 0 ] && continue

    pane_idx="${target##*.}"

    # Manifest: target, window_name, pane_cmd, pane_idx
    printf '%s\t%s\t%s\t%s\n' "$target" "$window_name" "$pane_cmd" "$pane_idx" >> "$INDEX_DIR/.manifest"
done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{window_name}	#{pane_current_command}')
