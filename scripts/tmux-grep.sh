#!/usr/bin/env bash
# Unified tmux session switcher + pane content search.
# Usage: tmux-grep.sh [--mode sessions|search]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMPDIR=$(mktemp -d "/tmp/tmux-grep.XXXXXX")
export TMPDIR
trap 'rm -rf "$TMPDIR"' EXIT

# Parse initial mode
MODE="sessions"
for arg in "$@"; do
    case "$arg" in
        --mode) shift; MODE="${1:-sessions}" ;;
        sessions|search) MODE="$arg" ;;
    esac
    shift 2>/dev/null || true
done
echo "$MODE" > "$TMPDIR/.mode"

# Context lines for search preview
CONTEXT=$(tmux show-option -gqv @grep-context 2>/dev/null || true)
CONTEXT="${CONTEXT:-5}"

# --- Unified preview: reads mode file to decide behavior ---
PREVIEW="
mode=\$(cat '$TMPDIR/.mode' 2>/dev/null || echo sessions);
line={};
if [ \"\$mode\" = 'search' ]; then
    tag=\$(echo \"\$line\" | cut -f1);
    field2=\$(echo \"\$line\" | cut -f2);
    if [ \"\$tag\" = 'H' ] || [ \"\$tag\" = 'E' ]; then
        tmux capture-pane -pJ -t \"\$field2\" 2>/dev/null || echo 'No preview';
    else
        target=\${field2%|*};
        line_num=\${field2#*|};
        file=\"$TMPDIR/pane_\$(echo \"\$target\" | tr ':.' '_')\";
        if [ -f \"\$file\" ]; then
            start=\$((line_num - ${CONTEXT})); [ \$start -lt 1 ] && start=1;
            end=\$((line_num + ${CONTEXT}));
            awk -v hl=\"\$line_num\" -v s=\"\$start\" -v e=\"\$end\" \\
                'NR>=s && NR<=e {
                    prefix = (NR==hl) ? \" → \" : \"   \"
                    printf \"%s%4d│ %s\n\", prefix, NR, \$0
                }' \"\$file\";
        fi
    fi
else
    tag=\$(echo \"\$line\" | cut -f1);
    target=\$(echo \"\$line\" | cut -f2);
    if [ \"\$tag\" = 'W' ]; then
        tmux capture-pane -pJ -t \"\${target}.0\" 2>/dev/null || echo 'No preview';
    else
        tmux capture-pane -pJ -t \"\$target\" 2>/dev/null || echo 'No preview';
    fi
fi
"

# --- Change handler: mode-aware reload on every keystroke ---
# In search mode: run filter.sh. In other modes: re-emit cached data for fzf's built-in filter.
CHANGE_CMD="mode=\$(cat '$TMPDIR/.mode' 2>/dev/null || echo sessions); if [ \"\$mode\" = 'search' ]; then bash '$SCRIPT_DIR/filter.sh' --dir '$TMPDIR' --query {q}; else cat \"$TMPDIR/.\${mode}-cache\" 2>/dev/null; fi"

# --- Mode switch helpers ---
SWITCH_TO_SESSIONS="bash '$SCRIPT_DIR/sessions.sh' sessions | tee '$TMPDIR/.sessions-cache' && echo sessions > '$TMPDIR/.mode'"
SWITCH_TO_WINDOWS="bash '$SCRIPT_DIR/sessions.sh' windows | tee '$TMPDIR/.windows-cache' && echo windows > '$TMPDIR/.mode'"
SWITCH_TO_SEARCH="bash '$SCRIPT_DIR/search.sh' --index-dir '$TMPDIR' && echo search > '$TMPDIR/.mode'"
SWITCH_SESSIONS_RESET="bash '$SCRIPT_DIR/sessions.sh' sessions --reset | tee '$TMPDIR/.sessions-cache' && echo sessions > '$TMPDIR/.mode'"

KILL_TARGET="bash '$SCRIPT_DIR/kill-target.sh' {}"

# Reload current mode after kill
RELOAD_AFTER_KILL="mode=\$(cat '$TMPDIR/.mode' 2>/dev/null || echo sessions); if [ \"\$mode\" = 'search' ]; then bash '$SCRIPT_DIR/search.sh' --index-dir '$TMPDIR' && bash '$SCRIPT_DIR/filter.sh' --dir '$TMPDIR' --query {q}; else bash '$SCRIPT_DIR/sessions.sh' \"\$mode\" | tee \"$TMPDIR/.\${mode}-cache\"; fi"

# Headers
HDR_SESSIONS="Sessions | tab: windows | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill | ctrl-d: cleanup"
HDR_WINDOWS="Sessions + Windows | btab: sessions | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill | ctrl-d: cleanup"
HDR_SEARCH="Search panes | ctrl-s/btab: sessions | tab: windows | ctrl-r: refresh | ctrl-x: kill | →/←: expand/collapse"

# --- Set initial state based on mode ---
if [ "$MODE" = "search" ]; then
    "$SCRIPT_DIR/search.sh" --index-dir "$TMPDIR"
    INITIAL_DATA=$("$SCRIPT_DIR/filter.sh" --dir "$TMPDIR" --query "")
    INITIAL_PROMPT="Search> "
    INITIAL_HEADER="$HDR_SEARCH"
    INITIAL_DISABLED="--disabled"
else
    INITIAL_DATA=$("$SCRIPT_DIR/sessions.sh" "$MODE")
    echo "$INITIAL_DATA" > "$TMPDIR/.${MODE}-cache"
    INITIAL_DISABLED=""
    if [ "$MODE" = "windows" ]; then
        INITIAL_PROMPT="Window> "
        INITIAL_HEADER="$HDR_WINDOWS"
    else
        INITIAL_PROMPT="Session> "
        INITIAL_HEADER="$HDR_SESSIONS"
    fi
fi

[ -z "$INITIAL_DATA" ] && { echo "No data found."; exit 0; }

# --- Run fzf ---
RESULT=$(echo "$INITIAL_DATA" | fzf \
    --ansi \
    --no-sort \
    --layout=reverse \
    --delimiter=$'\t' \
    --with-nth=3.. \
    --header="$INITIAL_HEADER" \
    --prompt="$INITIAL_PROMPT" \
    --preview="$PREVIEW" \
    --preview-window='right:45%:wrap' \
    --print-query \
    $INITIAL_DISABLED \
    --bind="change:reload($CHANGE_CMD)" \
    --bind="ctrl-j:preview-down,ctrl-k:preview-up" \
    --bind="tab:execute-silent($SWITCH_TO_WINDOWS)+enable-search+reload(cat '$TMPDIR/.windows-cache')+change-prompt(Window> )+change-header($HDR_WINDOWS)" \
    --bind="btab:execute-silent($SWITCH_TO_SESSIONS)+enable-search+reload(cat '$TMPDIR/.sessions-cache')+change-prompt(Session> )+change-header($HDR_SESSIONS)" \
    --bind="ctrl-/:execute-silent($SWITCH_TO_SEARCH)+disable-search+reload(bash '$SCRIPT_DIR/filter.sh' --dir '$TMPDIR' --query {q})+change-prompt(Search> )+change-header($HDR_SEARCH)" \
    --bind="ctrl-s:execute-silent($SWITCH_TO_SESSIONS)+enable-search+reload(cat '$TMPDIR/.sessions-cache')+change-prompt(Session> )+change-header($HDR_SESSIONS)" \
    --bind="ctrl-r:execute-silent($SWITCH_SESSIONS_RESET)+enable-search+reload(cat '$TMPDIR/.sessions-cache')+change-prompt(Session> )+change-header($HDR_SESSIONS)" \
    --bind="ctrl-x:execute-silent($KILL_TARGET)+reload($RELOAD_AFTER_KILL)" \
    --bind="ctrl-e:execute-silent(bash '$SCRIPT_DIR/toggle-expand.sh' {1} {2} '$TMPDIR')+reload(bash '$SCRIPT_DIR/filter.sh' --dir '$TMPDIR' --query {q})" \
    --bind="right:execute-silent(bash '$SCRIPT_DIR/toggle-expand.sh' E {2} '$TMPDIR')+reload(bash '$SCRIPT_DIR/filter.sh' --dir '$TMPDIR' --query {q})" \
    --bind="left:execute-silent(bash '$SCRIPT_DIR/toggle-expand.sh' H {2} '$TMPDIR')+reload(bash '$SCRIPT_DIR/filter.sh' --dir '$TMPDIR' --query {q})" \
    --bind="ctrl-d:become(bash '$SCRIPT_DIR/cleanup-mode.sh')" \
) || exit 0

# Parse: first line = query, last line = selection
QUERY=$(head -1 <<< "$RESULT")
SELECTION=$(tail -1 <<< "$RESULT")

[ -z "$SELECTION" ] && exit 0

exec bash "$SCRIPT_DIR/handle-selection.sh" "$QUERY" "$SELECTION"
