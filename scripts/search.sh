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

# Collapse grouped sessions to one visible representative in search results.
declare -a SESSION_ROWS=()
declare -A GROUP_ROOT_EXISTS
declare -A GROUP_REP_SESSION
declare -A GROUP_REP_ATTACHED
declare -A GROUP_REP_ACTIVITY

while IFS=$'\t' read -r sname sattached sactivity sgroup; do
    SESSION_ROWS+=("${sname}"$'\t'"${sattached}"$'\t'"${sactivity}"$'\t'"${sgroup}")
    if [ -n "$sgroup" ] && [ "$sname" = "$sgroup" ]; then
        GROUP_ROOT_EXISTS["$sgroup"]=1
    fi
done < <(tmux list-sessions -F '#{session_name}	#{session_attached}	#{session_activity}	#{session_group}' 2>/dev/null)

for row in "${SESSION_ROWS[@]}"; do
    IFS=$'\t' read -r sname sattached sactivity sgroup <<< "$row"
    key="${sgroup:-$sname}"

    if [ -n "$sgroup" ] && [ -n "${GROUP_ROOT_EXISTS[$key]+x}" ]; then
        [ "$sname" = "$key" ] || continue
    fi

    if [ -z "${GROUP_REP_SESSION[$key]+x}" ] || \
       [ "$sattached" -gt "${GROUP_REP_ATTACHED[$key]:-0}" ] || \
       { [ "$sattached" -eq "${GROUP_REP_ATTACHED[$key]:-0}" ] && [ "$sactivity" -gt "${GROUP_REP_ACTIVITY[$key]:-0}" ]; }; then
        GROUP_REP_SESSION["$key"]="$sname"
        GROUP_REP_ATTACHED["$key"]="$sattached"
        GROUP_REP_ACTIVITY["$key"]="$sactivity"
    fi
done

# Capture all panes' scrollback and build manifest
while IFS=$'\t' read -r session_name window_idx pane_idx pane_id window_name pane_cmd sgroup; do
    key="${sgroup:-$session_name}"
    rep_session="${GROUP_REP_SESSION[$key]:-$session_name}"
    [ "$session_name" = "$rep_session" ] || continue

    target="${rep_session}:${window_idx}.${pane_idx}"
    safe="${target//[:.]/_}"
    outfile="${INDEX_DIR}/pane_${safe}"

    tmux capture-pane -p -S "$DEPTH" -t "$target" > "$outfile" 2>/dev/null || continue

    total=$(wc -l < "$outfile")
    [ "$total" -eq 0 ] && continue

    pane_idx="${target##*.}"

    # Manifest: target, window_name, pane_cmd, pane_idx
    printf '%s\t%s\t%s\t%s\n' "$target" "$window_name" "$pane_cmd" "$pane_idx" >> "$INDEX_DIR/.manifest"
done < <(tmux list-panes -a -F '#{session_name}	#{window_index}	#{pane_index}	#{pane_id}	#{window_name}	#{pane_current_command}	#{session_group}')
