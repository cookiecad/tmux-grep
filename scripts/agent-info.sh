#!/usr/bin/env bash
# Shared helper: batch agent detection, title lookup, status reading.
# Sourced (not executed) by other scripts — defines functions and associative arrays.

STATUS_DIR="$HOME/.cache/tmux-agent-status"

# AGENT_BY_PANE_PID[pane_pid] = "agent_type session_id"
declare -gA AGENT_BY_PANE_PID
# TITLE_BY_SESSION_ID[session_id] = "summary text"
declare -gA TITLE_BY_SESSION_ID

build_agent_map() {
    AGENT_BY_PANE_PID=()

    # One ps call to find all claude/codex processes.
    # Match by PPID (shell → claude) AND by PID (pane started claude directly).
    while read -r pid ppid args; do
        # Skip vscode embedded claude
        [[ "$args" == *"--output-format"* ]] && continue
        [[ "$args" == *".vscode"* ]] && continue

        local agent_type="claude"
        [[ "$args" == *codex* ]] && agent_type="codex"

        local session_id=""
        if [[ "$args" =~ --resume[[:space:]]+([a-f0-9-]+) ]]; then
            session_id="${BASH_REMATCH[1]}"
        elif [[ "$args" =~ resume[[:space:]]+([a-f0-9-]+) ]]; then
            session_id="${BASH_REMATCH[1]}"
        fi

        local val="$agent_type $session_id"
        # Store by PPID (common case: shell is pane_pid, claude is child)
        AGENT_BY_PANE_PID["$ppid"]="$val"
        # Also store by PID (for panes that started claude directly)
        AGENT_BY_PANE_PID["$pid"]="$val"
    done < <(ps -eo pid,ppid,args --no-headers 2>/dev/null | grep -E '[c]laude|[c]odex' | grep -v grep)
}

build_title_cache() {
    TITLE_BY_SESSION_ID=()

    # Collect session IDs we need titles for (from agent map)
    local needed_sids=""
    for val in "${AGENT_BY_PANE_PID[@]}"; do
        local sid="${val#* }"
        [ -n "$sid" ] && needed_sids+="$sid "
    done

    while IFS=$'\t' read -r sid summary; do
        [ -n "$sid" ] && TITLE_BY_SESSION_ID["$sid"]="$summary"
    done < <(python3 -c "
import json, glob, os, sys

needed = set(sys.argv[1].split()) if sys.argv[1].strip() else set()

# Phase 1: sessions-index.json (fast, covers completed sessions)
found = set()
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/sessions-index.json')):
    try:
        with open(f) as fh:
            data = json.load(fh)
        for e in data.get('entries', []):
            sid = e.get('sessionId', '')
            summary = e.get('summary', '')
            if sid and summary:
                print(f'{sid}\t{summary}')
                found.add(sid)
    except Exception:
        pass

# Phase 2: for unfound active sessions, extract first user prompt from JSONL
still_needed = needed - found
if still_needed:
    for sid in still_needed:
        # Find the JSONL file
        matches = glob.glob(os.path.expanduser(f'~/.claude/projects/*/{sid}.jsonl'))
        for jf in matches:
            try:
                with open(jf) as fh:
                    for line in fh:
                        d = json.loads(line)
                        if d.get('type') == 'user':
                            msg = d.get('message', {})
                            if isinstance(msg, dict):
                                content = msg.get('content', '')
                                if isinstance(content, str) and content:
                                    # Truncate to first sentence or 80 chars
                                    title = content.split('.')[0].split('\\n')[0][:80]
                                    print(f'{sid}\t{title}')
                            break
            except Exception:
                pass
" "$needed_sids" 2>/dev/null)
}

get_agent_status() {
    local session="$1"
    local status_file="$STATUS_DIR/${session}.status"
    local remote_file="$STATUS_DIR/${session}-remote.status"
    local wait_file="$STATUS_DIR/wait/${session}.wait"

    if [ -f "$remote_file" ]; then
        cat "$remote_file" 2>/dev/null
        return
    fi

    if [ -f "$status_file" ]; then
        local status
        status=$(cat "$status_file" 2>/dev/null)
        if [ "$status" = "wait" ] && [ ! -f "$wait_file" ]; then
            echo "done" > "$status_file" 2>/dev/null
            echo "done"
        else
            echo "$status"
        fi
    fi
}

get_wait_info() {
    local session="$1"
    local wait_file="$STATUS_DIR/wait/${session}.wait"
    if [ -f "$wait_file" ]; then
        local expiry current remaining
        expiry=$(cat "$wait_file" 2>/dev/null)
        current=$(date +%s)
        remaining=$(( expiry - current ))
        if [ "$remaining" -gt 0 ]; then
            echo "($(( remaining / 60 ))m)"
        fi
    fi
}

is_ssh_session() {
    local session="$1"
    tmux list-panes -t "$session" -F "#{pane_current_command}" 2>/dev/null | grep -q "^ssh$"
}
