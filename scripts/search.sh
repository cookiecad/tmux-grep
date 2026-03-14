#!/usr/bin/env bash
# Generates pane content search index. Outputs TSV lines with mode tag "G".
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

# Capture all panes' scrollback and build index
while IFS=$'\t' read -r target window_name pane_cmd; do
    safe="${target//[:.]/_}"
    outfile="${INDEX_DIR}/pane_${safe}"

    tmux capture-pane -p -S "$DEPTH" -t "$target" > "$outfile" 2>/dev/null || continue

    total=$(wc -l < "$outfile")
    [ "$total" -eq 0 ] && continue

    # Build label
    label="$target $window_name"
    if [[ "$pane_cmd" != "bash" && "$pane_cmd" != "zsh" && "$pane_cmd" != "fish" ]]; then
        label="${label} (${pane_cmd})"
    fi

    # Output: G<TAB>target<TAB>total_lines<TAB>line_num<TAB>label<TAB>content
    awk -v t="$target" -v total="$total" -v label="$label" \
        'NF > 0 {printf "G\t%s\t%s\t%d\t%s\t%s\n", t, total, NR, label, $0}' "$outfile"
done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{window_name}	#{pane_current_command}')
