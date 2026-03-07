#!/usr/bin/env bash
set -euo pipefail

TMPDIR=$(mktemp -d "/tmp/tmux-grep.XXXXXX")
trap 'rm -rf "$TMPDIR"' EXIT

# Options (configurable via tmux set -g @grep-*)
DEPTH=$(tmux show-option -gqv @grep-depth 2>/dev/null || true)
DEPTH="${DEPTH:--5000}"
CONTEXT=$(tmux show-option -gqv @grep-context 2>/dev/null || true)
CONTEXT="${CONTEXT:-5}"

# Phase 1: Capture all panes' scrollback
while IFS=$'\t' read -r target window_name pane_cmd; do
    safe="${target//[:.]/_}"
    outfile="${TMPDIR}/pane_${safe}"

    tmux capture-pane -p -S "$DEPTH" -t "$target" > "$outfile" 2>/dev/null || continue

    total=$(wc -l < "$outfile")
    [ "$total" -eq 0 ] && continue

    # Build label: session:window_name (command) if not a shell
    label="$target $window_name"
    if [[ "$pane_cmd" != "bash" && "$pane_cmd" != "zsh" && "$pane_cmd" != "fish" ]]; then
        label="${label} (${pane_cmd})"
    fi

    # Index format: target<TAB>total_lines<TAB>line_num<TAB>label<TAB>content
    # Skip blank lines to reduce noise
    awk -v t="$target" -v total="$total" -v label="$label" \
        'NF > 0 {printf "%s\t%s\t%d\t%s\t%s\n", t, total, NR, label, $0}' "$outfile"
done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{window_name}	#{pane_current_command}') \
> "${TMPDIR}/index"

if [ ! -s "${TMPDIR}/index" ]; then
    echo "No pane content found."
    exit 0
fi

# Phase 2: fzf selection
# Preview shows context around the matched line
PREVIEW_CMD="
    file=\"${TMPDIR}/pane_\$(echo {1} | tr ':.' '_')\"
    line={3}
    start=\$((line - ${CONTEXT})); [ \$start -lt 1 ] && start=1
    end=\$((line + ${CONTEXT}))
    awk -v hl=\"\$line\" -v s=\"\$start\" -v e=\"\$end\" \\
        'NR>=s && NR<=e {
            prefix = (NR==hl) ? \" → \" : \"   \"
            printf \"%s%4d│ %s\n\", prefix, NR, \$0
        }' \"\$file\"
"

result=$(cat "${TMPDIR}/index" | fzf \
    --exact \
    --delimiter=$'\t' \
    --with-nth=4,5 \
    --nth=5 \
    --no-sort \
    --layout=reverse \
    --print-query \
    --header='Search all tmux panes (prefix+/ to reopen)' \
    --preview="$PREVIEW_CMD" \
    --preview-window='up:12:wrap' \
    --bind='ctrl-s:toggle-sort' \
) || exit 0

# Phase 3: Parse selection and navigate to match
query=$(head -1 <<< "$result")
selection=$(tail -1 <<< "$result")

IFS=$'\t' read -r target total line_num label content <<< "$selection"

# Switch to the target pane
tmux select-window -t "${target%.*}"
tmux select-pane -t "$target"

# Enter copy-mode and position at the exact match line
tmux copy-mode -t "$target"
tmux send-keys -t "$target" -X history-top

# Position one line above the match, then search-forward finds it
if [ "$line_num" -gt 1 ]; then
    tmux send-keys -t "$target" -X -N "$((line_num - 2))" cursor-down
fi

# Search forward to highlight the match and enable n/N navigation
if [ -n "$query" ]; then
    tmux send-keys -t "$target" -X search-forward "$query"
fi
