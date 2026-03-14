#!/usr/bin/env bash
# Generates session list (--mode sessions) or session+window list (--mode windows).
# Output is TSV with a hidden mode tag in field 1 for dispatch.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/agent-info.sh"

MODE="sessions"
RESET=false
for arg in "$@"; do
    case "$arg" in
        --mode) shift; MODE="${1:-sessions}" ;;
        sessions|windows) MODE="$arg" ;;
        --reset) RESET=true ;;
    esac
    shift 2>/dev/null || true
done

if [ "$RESET" = true ]; then
    for status_file in "$STATUS_DIR"/*.status; do
        [ ! -f "$status_file" ] && continue
        session_name=$(basename "$status_file" .status)
        [[ "$session_name" == *"-remote" ]] && continue
        rm -f "$STATUS_DIR/wait/${session_name}.wait" 2>/dev/null
        if [ "$(cat "$status_file" 2>/dev/null)" = "wait" ]; then
            echo "done" > "$status_file" 2>/dev/null
        fi
    done
fi

build_agent_map
build_title_cache

# Build pane-level agent info
declare -A PANE_AGENTS
declare -A SESSION_HAS_AGENT

while IFS=$'\t' read -r target pane_pid; do
    if [ -n "${AGENT_BY_PANE_PID[$pane_pid]+x}" ]; then
        _sw="${target%.*}"
        PANE_AGENTS["$_sw"]="${AGENT_BY_PANE_PID[$pane_pid]}"
        _session="${target%%:*}"
        SESSION_HAS_AGENT["$_session"]=1
    fi
done < <(tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index}	#{pane_pid}' 2>/dev/null)

# Also mark sessions that have status files (e.g. SSH remote agents)
for _sf in "$STATUS_DIR"/*.status; do
    [ ! -f "$_sf" ] && continue
    _sname=$(basename "$_sf" .status)
    [[ "$_sname" == *"-remote" ]] && continue
    _st=$(cat "$_sf" 2>/dev/null)
    [ -n "$_st" ] && SESSION_HAS_AGENT["$_sname"]=1
done

format_status() {
    local status="$1" wait_info="$2"
    case "$status" in
        working) printf '\033[1;33m[working]\033[0m' ;;
        done)    printf '\033[1;32m[done]\033[0m' ;;
        wait)    printf '\033[1;36m[wait]\033[0m %s' "$wait_info" ;;
        *)       printf '\033[1;90m[no agent]\033[0m' ;;
    esac
}

get_agent_title_for_session() {
    local session="$1"
    for key in "${!PANE_AGENTS[@]}"; do
        if [[ "$key" == "$session:"* ]]; then
            local info="${PANE_AGENTS[$key]}"
            local sid="${info#* }"
            if [ -n "$sid" ] && [ -n "${TITLE_BY_SESSION_ID[$sid]+x}" ]; then
                echo "${TITLE_BY_SESSION_ID[$sid]}"
                return
            fi
        fi
    done
}

get_agent_title_for_window() {
    local sw="$1"
    if [ -n "${PANE_AGENTS[$sw]+x}" ]; then
        local info="${PANE_AGENTS[$sw]}"
        local sid="${info#* }"
        if [ -n "$sid" ] && [ -n "${TITLE_BY_SESSION_ID[$sid]+x}" ]; then
            echo "${TITLE_BY_SESSION_ID[$sid]}"
            return
        fi
    fi
}

truncate_title() {
    local t="$1" max="${2:-50}"
    if [ ${#t} -gt "$max" ]; then
        echo "${t:0:$((max-3))}..."
    else
        echo "$t"
    fi
}

emit_session_line() {
    local name="$1" windows="$2" attached="$3"

    _ssh=""
    is_ssh_session "$name" && _ssh=" [ssh]"

    if [ -n "${SESSION_HAS_AGENT[$name]+x}" ]; then
        _status=$(get_agent_status "$name")
        [ -z "$_status" ] && _status="done"
        _wait_info=""
        [ "$_status" = "wait" ] && _wait_info=$(get_wait_info "$name")
        _status_display=$(format_status "$_status" "$_wait_info")
    else
        _status_display=$(format_status "" "")
    fi

    _title=$(get_agent_title_for_session "$name")
    _title_display=""
    if [ -n "$_title" ]; then
        _title=$(truncate_title "$_title" 45)
        _title_display="  \"${_title}\""
    fi

    _display=$(printf "%-18s %2s win  %-10s %b%s%s" \
        "$name" "$windows" "$attached" "$_status_display" "$_ssh" "$_title_display")

    printf 'S\t%s\t%s\n' "$name" "$_display"
}

if [ "$MODE" = "sessions" ]; then
    while IFS=$'\t' read -r name windows attached; do
        emit_session_line "$name" "$windows" "$attached"
    done < <(tmux list-sessions -F '#{session_name}	#{session_windows}	#{?session_attached,(attached),}' 2>/dev/null)

elif [ "$MODE" = "windows" ]; then
    while IFS=$'\t' read -r sess_name sess_windows sess_attached; do
        # Session header
        _ssh=""
        is_ssh_session "$sess_name" && _ssh=" [ssh]"

        if [ -n "${SESSION_HAS_AGENT[$sess_name]+x}" ]; then
            _status=$(get_agent_status "$sess_name")
            [ -z "$_status" ] && _status="done"
            _wait_info=""
            [ "$_status" = "wait" ] && _wait_info=$(get_wait_info "$sess_name")
            _status_display=$(format_status "$_status" "$_wait_info")
        else
            _status_display=$(format_status "" "")
        fi

        _header=$(printf "\033[1m%-18s\033[0m %2s win  %-10s %b%s" \
            "$sess_name" "$sess_windows" "$sess_attached" "$_status_display" "$_ssh")
        printf 'S\t%s\t%s\n' "$sess_name" "$_header"

        # Windows — aligned table: address  name  process  dir  title
        while IFS=$'\t' read -r win_idx win_name pane_cmd pane_path; do
            _sw="${sess_name}:${win_idx}"
            _title_display=""
            _cmd_display=""

            if [ -n "${PANE_AGENTS[$_sw]+x}" ]; then
                _info="${PANE_AGENTS[$_sw]}"
                _agent_type="${_info%% *}"
                _title=$(get_agent_title_for_window "$_sw")
                if [ -n "$_title" ]; then
                    _title=$(truncate_title "$_title" 40)
                    _title_display="\"${_title}\""
                fi
                _cmd_display="$_agent_type"
            else
                case "$pane_cmd" in bash|zsh|fish) ;; *) _cmd_display="$pane_cmd" ;; esac
            fi

            # Shorten path: strip home, projects/, and long intermediate dirs
            if [ "$pane_path" = "/home/nathan" ] || [ "$pane_path" = "/home/nathan/" ]; then
                _dir="~"
            elif [[ "$pane_path" == /home/nathan/* ]]; then
                _dir="${pane_path#/home/nathan/}"
                _dir="${_dir#projects/}"
                # Collapse worktree paths: foo-worktrees/branch → foo/branch
                _dir=$(echo "$_dir" | sed 's/-worktrees\//\//g')
                # Collapse .claude/worktrees → .worktrees
                _dir="${_dir/.claude\/worktrees/.wt}"
            else
                _dir="$pane_path"
            fi
            # Truncate long paths from the left
            if [ ${#_dir} -gt 30 ]; then
                _dir="..${_dir: -28}"
            fi

            # Truncate long window names
            if [ ${#win_name} -gt 12 ]; then
                win_name="${win_name:0:11}~"
            fi

            _win_display=$(printf "  %-22s %-13s %-8s %-25s %s" \
                "${sess_name}:${win_idx}" "$win_name" "$_cmd_display" "$_dir" "$_title_display")

            printf 'W\t%s:%s\t%s\n' "$sess_name" "$win_idx" "$_win_display"
        done < <(tmux list-windows -t "$sess_name" -F '#{window_index}	#{window_name}	#{pane_current_command}	#{pane_current_path}' 2>/dev/null)
    done < <(tmux list-sessions -F '#{session_name}	#{session_windows}	#{?session_attached,(attached),}' 2>/dev/null)
fi
