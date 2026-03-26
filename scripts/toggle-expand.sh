#!/usr/bin/env bash
# Toggles expand/collapse state for a search result group.
# Usage: toggle-expand.sh TAG ID DIR
#   TAG = E (expand) or H (collapse)
#   ID  = pane target or target|line_num (line_num stripped automatically)
#   DIR = temp directory containing .expanded file

set -euo pipefail

TAG="${1:-}"
ID="${2:-}"
DIR="${3:-}"

[ -z "$TAG" ] || [ -z "$ID" ] || [ -z "$DIR" ] && exit 0

# Strip line number if present (G-line field2 is target|line_num)
ID="${ID%|*}"

EXPANDED="$DIR/.expanded"

if [ "$TAG" = "E" ]; then
    # Expand: add group (avoid duplicates)
    if ! grep -qxF "$ID" "$EXPANDED" 2>/dev/null; then
        echo "$ID" >> "$EXPANDED"
    fi
elif [ "$TAG" = "H" ]; then
    # Collapse: remove group from expanded list
    if [ -f "$EXPANDED" ]; then
        grep -vxF "$ID" "$EXPANDED" > "$EXPANDED.tmp" 2>/dev/null || true
        mv "$EXPANDED.tmp" "$EXPANDED"
    fi
fi
