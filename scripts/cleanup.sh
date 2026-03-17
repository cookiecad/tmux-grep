#!/usr/bin/env bash
# Generates a list of idle panes for cleanup triage.
# Classifies each as: blank (just prompt), stale (idle >1hr), or has-output.
# Output: TSV with mode tag "C" for cleanup dispatch.

set -uo pipefail

NOW=$(date +%s)
STALE_THRESHOLD=$((60 * 60))  # 1 hour

# Collect all panes with metadata
while IFS=$'\t' read -r target sess_name win_idx win_name pane_cmd pane_pid pane_path win_activity; do
    # Only consider idle shells
    case "$pane_cmd" in
        bash|zsh|fish|sh) ;;
        *) continue ;;
    esac

    # Skip if shell has child processes (something running in fg/bg)
    children=$(ps --ppid "$pane_pid" --no-headers 2>/dev/null | wc -l)
    [ "$children" -gt 0 ] && continue

    # Measure scrollback content
    content=$(tmux capture-pane -p -t "$target" 2>/dev/null || true)
    line_count=$(echo "$content" | grep -c '[^[:space:]]' || true)

    # Classify
    idle_seconds=$(( NOW - win_activity ))
    idle_display=""
    if [ "$idle_seconds" -ge 86400 ]; then
        idle_display="$(( idle_seconds / 86400 ))d"
    elif [ "$idle_seconds" -ge 3600 ]; then
        idle_display="$(( idle_seconds / 3600 ))h"
    elif [ "$idle_seconds" -ge 60 ]; then
        idle_display="$(( idle_seconds / 60 ))m"
    else
        idle_display="${idle_seconds}s"
    fi

    if [ "$line_count" -le 2 ]; then
        category="blank"
        cat_display=$'\033[1;31m[blank]\033[0m'
    elif [ "$idle_seconds" -ge "$STALE_THRESHOLD" ]; then
        category="stale"
        cat_display=$'\033[1;33m[stale]\033[0m'
    else
        category="output"
        cat_display=$'\033[1;36m[has output]\033[0m'
    fi

    # Shorten path
    if [ "$pane_path" = "/home/nathan" ] || [ "$pane_path" = "/home/nathan/" ]; then
        _dir="~"
    elif [[ "$pane_path" == /home/nathan/* ]]; then
        _dir="${pane_path#/home/nathan/}"
        _dir="${_dir#projects/}"
        _dir=$(echo "$_dir" | sed 's/-worktrees\//\//g')
        _dir="${_dir/.claude\/worktrees/.wt}"
    else
        _dir="$pane_path"
    fi
    if [ ${#_dir} -gt 25 ]; then
        _dir="..${_dir: -23}"
    fi

    # Truncate window name
    _wname="$win_name"
    if [ ${#_wname} -gt 12 ]; then
        _wname="${_wname:0:11}~"
    fi

    _display=$(printf "%-22s %-13s %b  %-5s  %-25s" \
        "${sess_name}:${win_idx}" "$_wname" "$cat_display" "$idle_display" "$_dir")

    # Sort key: blank first (0), then stale (1), then has-output (2); within each by idle time desc
    case "$category" in
        blank)  sort_key=$(printf "0_%010d" $((999999999 - idle_seconds))) ;;
        stale)  sort_key=$(printf "1_%010d" $((999999999 - idle_seconds))) ;;
        output) sort_key=$(printf "2_%010d" $((999999999 - idle_seconds))) ;;
    esac

    printf '%s\tC\t%s\t%s\n' "$sort_key" "$target" "$_display"

done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{session_name}	#{window_index}	#{window_name}	#{pane_current_command}	#{pane_pid}	#{pane_current_path}	#{window_activity}' 2>/dev/null)  |
    sort | cut -f2-  # Sort by key, then strip it
