#!/usr/bin/env bash
# Filters and groups search results with sticky headers and truncation.
# Reads the manifest + pane index files built by search.sh.
# Usage: filter.sh --dir DIR --query QUERY

set -euo pipefail

DIR=""
QUERY=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dir) DIR="${2:-}"; shift 2 ;;
        --query) QUERY="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

[ -z "$DIR" ] && exit 1

MANIFEST="$DIR/.manifest"
[ ! -f "$MANIFEST" ] && exit 0

EXPANDED="$DIR/.expanded"
SHOW_LIMIT=10

while IFS=$'\t' read -r target window_name pane_cmd pane_idx; do
    safe="${target//[:.]/_}"
    pane_file="$DIR/pane_${safe}"
    [ ! -f "$pane_file" ] && continue

    # Find matches → temp file (avoids storing huge match sets in memory)
    match_file="$DIR/.matches_${safe}"
    if [ -z "$QUERY" ]; then
        awk 'NF > 0 {printf "%d\t%s\n", NR, $0}' "$pane_file" > "$match_file"
    else
        grep -inF "$QUERY" "$pane_file" | sed 's/^\([0-9]*\):/\1\t/' > "$match_file" || true
    fi

    match_count=$(wc -l < "$match_file")
    [ "$match_count" -eq 0 ] && continue

    # Build header label
    session="${target%%:*}"
    header_label="${session}/${window_name}"
    if [[ "$pane_cmd" != "bash" && "$pane_cmd" != "zsh" && "$pane_cmd" != "fish" && "$pane_cmd" != "$window_name" ]]; then
        header_label="${header_label} (${pane_cmd})"
    fi
    if [ "$pane_idx" != "0" ]; then
        header_label="${header_label} .${pane_idx}"
    fi

    # Header line (always shown)
    printf 'H\t%s\t\033[1;36m── %s (%d matches) ──\033[0m\n' "$target" "$header_label" "$match_count"

    # Check if this group is expanded
    is_expanded=false
    if [ -f "$EXPANDED" ] && grep -qxF "$target" "$EXPANDED" 2>/dev/null; then
        is_expanded=true
    fi

    # Emit match lines — single awk pass handles truncation without SIGPIPE
    if [ "$is_expanded" = true ] || [ "$match_count" -le $((SHOW_LIMIT * 2)) ]; then
        # Show all matches
        awk -F'\t' -v t="$target" '{printf "G\t%s|%s\t    %s\n", t, $1, $2}' "$match_file"
    else
        # First N, expand marker, last N — all in one awk pass
        awk -F'\t' -v t="$target" -v limit="$SHOW_LIMIT" -v total="$match_count" '
        BEGIN { hidden = total - limit * 2 }
        NR <= limit { printf "G\t%s|%s\t    %s\n", t, $1, $2 }
        NR == limit + 1 { printf "E\t%s\t    \033[90m[...%d more matches — ctrl-e to expand...]\033[0m\n", t, hidden }
        NR > total - limit { printf "G\t%s|%s\t    %s\n", t, $1, $2 }
        ' "$match_file"
    fi
done < "$MANIFEST"
