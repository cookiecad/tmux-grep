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
    target=\$(echo \"\$line\" | cut -f2);
    line_num=\$(echo \"\$line\" | cut -f4);
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

# --- Reload helper scripts that also update the mode file ---
RELOAD_SESSIONS="bash '$SCRIPT_DIR/sessions.sh' sessions && echo sessions > '$TMPDIR/.mode'"
RELOAD_WINDOWS="bash '$SCRIPT_DIR/sessions.sh' windows && echo windows > '$TMPDIR/.mode'"
RELOAD_SEARCH="bash '$SCRIPT_DIR/search.sh' --index-dir '$TMPDIR' && echo search > '$TMPDIR/.mode'"
RELOAD_SESSIONS_RESET="bash '$SCRIPT_DIR/sessions.sh' sessions --reset && echo sessions > '$TMPDIR/.mode'"
KILL_TARGET="bash '$SCRIPT_DIR/kill-target.sh' {}"
# Reload current mode after kill
RELOAD_CURRENT="mode=\$(cat '$TMPDIR/.mode' 2>/dev/null || echo sessions); bash '$SCRIPT_DIR/sessions.sh' \$mode"

# --- Set initial state based on mode ---
if [ "$MODE" = "search" ]; then
    INITIAL_DATA=$("$SCRIPT_DIR/search.sh" --index-dir "$TMPDIR")
    INITIAL_PROMPT="Search> "
    INITIAL_HEADER="Search panes | ctrl-s/btab: sessions | tab: windows | ctrl-r: refresh | ctrl-x: kill"
else
    INITIAL_DATA=$("$SCRIPT_DIR/sessions.sh" "$MODE")
    if [ "$MODE" = "windows" ]; then
        INITIAL_PROMPT="Window> "
        INITIAL_HEADER="Sessions + Windows | btab: sessions | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill"
    else
        INITIAL_PROMPT="Session> "
        INITIAL_HEADER="Sessions | tab: windows | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill"
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
    --bind="j:down,k:up,ctrl-j:preview-down,ctrl-k:preview-up" \
    --bind="tab:reload($RELOAD_WINDOWS)+change-prompt(Window> )+change-header(Sessions + Windows | btab: sessions | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill)" \
    --bind="btab:reload($RELOAD_SESSIONS)+change-prompt(Session> )+change-header(Sessions | tab: windows | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill)" \
    --bind="ctrl-/:reload($RELOAD_SEARCH)+change-prompt(Search> )+change-header(Search panes | ctrl-s/btab: sessions | tab: windows | ctrl-r: refresh | ctrl-x: kill)" \
    --bind="ctrl-s:reload($RELOAD_SESSIONS)+change-prompt(Session> )+change-header(Sessions | tab: windows | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill)" \
    --bind="ctrl-r:reload($RELOAD_SESSIONS_RESET)+change-prompt(Session> )+change-header(Sessions | tab: windows | ctrl-/: search | ctrl-r: refresh | ctrl-x: kill)" \
    --bind="ctrl-x:execute($KILL_TARGET)+reload($RELOAD_CURRENT)" \
) || exit 0

# Parse: first line = query, last line = selection
QUERY=$(head -1 <<< "$RESULT")
SELECTION=$(tail -1 <<< "$RESULT")

[ -z "$SELECTION" ] && exit 0

exec bash "$SCRIPT_DIR/handle-selection.sh" "$QUERY" "$SELECTION"
