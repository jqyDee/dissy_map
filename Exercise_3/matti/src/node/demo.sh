#!/usr/bin/env bash
# Opens a new tmux window with one pane per node and runs a demo scenario.
# Inside tmux the window is added to the current session; outside tmux it is
# added to (or creates) the session "dissy".
#
# usage: ./demo.sh <scenario>      (./demo.sh without arguments lists them)
#
# Each pane keeps its shell after the node exits (q), so a node can be
# restarted by hand with arrow-up + enter.
set -euo pipefail
cd "$(dirname "$0")"

BIN=./target/debug/node
SESSION=dissy

usage() {
    cat <<EOF
usage: $0 <scenario>

Task 1 - discovery
  task1                 A, B, C discover each other
  task1-rejoin          like task1; B quits cleanly at 15s and restarts at 30s
  task1-crash           like task1; B is killed (SIGKILL) at 15s and restarts at 30s

Task 2 - publish/subscribe
  task2                 A, B, C publish "Hello from Node X" every second

Task 3 - byzantine generals (commander starts 3s after the lieutenants)
  task3-loyal           3 nodes, all loyal
  task3-traitor-cmd     3 nodes, traitor commander
  task3-traitor-lieut   3 nodes, traitor lieutenant L2
  task4-loyal           4 nodes, all loyal
  task4-traitor-cmd     4 nodes, traitor commander
  task4-traitor-lieut   4 nodes, traitor lieutenant L3

Quit a node with q. Starting another demo closes the previous demo window.
EOF
    exit 1
}

# discovery / hello node: node <name> [subcommand]
node() {
    echo "$BIN --name $1 ${2:-discover}"
}

# byzantine general: general <name> <commander|lieutenant> <lieutenants> [--traitor]
general() {
    echo "$BIN --name $1 byzantine --role $2 --lieutenants $3 ${4:-}"
}

# start "title|command" ...: one pane per argument, tiled
start() {
    cargo build -q

    close_old_demos
    # leftover nodes of an earlier run would join this demo via mdns
    pkill -f -- "$BIN --name " 2>/dev/null || true
    sleep 1

    # -d: do not switch to the window yet; -c: panes start in this directory
    local new=(new-window -d -n "demo-$scenario" -c "$PWD" -P -F '#{pane_id}')
    if [ -z "${TMUX:-}" ]; then
        if tmux has-session -t "$SESSION" 2>/dev/null; then
            new+=(-t "$SESSION:")
        else
            new=(new-session -d -s "$SESSION" -n "demo-$scenario" -c "$PWD" -x 240 -y 60 -P -F '#{pane_id}')
        fi
    fi
    # pane ids instead of indices, so a custom pane-base-index does not matter
    PANES=("$(tmux "${new[@]}")")
    for ((i = 1; i < $#; i++)); do
        PANES+=("$(tmux split-window -t "${PANES[0]}" -c "$PWD" -P -F '#{pane_id}')")
        tmux select-layout -t "${PANES[0]}" tiled
    done
    tmux set-option -w -t "${PANES[0]}" pane-border-status top

    local i=0
    for entry in "$@"; do
        tmux select-pane -t "${PANES[$i]}" -T "${entry%%|*}"
        tmux send-keys -t "${PANES[$i]}" "${entry#*|}" Enter
        i=$((i + 1))
    done
}

# after starting: let B leave at 15s (q = clean, kill = crash) and rejoin at 30s
leave_and_rejoin() {
    local how=$1 pane=${PANES[1]} cmd
    cmd=$(node B)
    (
        sleep 15
        if [ "$how" = clean ]; then
            tmux send-keys -t "$pane" q
        else
            pkill -KILL -f -- "$BIN --name B " || true
        fi
        sleep 15
        tmux send-keys -t "$pane" "$cmd" Enter
    ) >/dev/null 2>&1 &
}

# close demo windows of earlier runs, except the one this script runs in
close_old_demos() {
    local session=() current=""
    if [ -n "${TMUX:-}" ]; then
        # the window of the pane this script runs in, not the active window
        current=$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}')
    elif tmux has-session -t "$SESSION" 2>/dev/null; then
        session=(-t "$SESSION")
    else
        return
    fi
    # ${a[@]+...}: an empty array counts as unbound under set -u in bash 3.2
    tmux list-windows ${session[@]+"${session[@]}"} -F '#{window_id} #{window_name}' |
        while read -r id name; do
            if [[ $name == demo-* && $id != "$current" ]]; then
                tmux kill-window -t "$id"
            fi
        done
}

show() {
    [ -n "${NO_ATTACH:-}" ] && return
    tmux select-pane -t "${PANES[0]}"
    tmux select-window -t "${PANES[0]}"
    if [ -z "${TMUX:-}" ]; then
        tmux attach -t "$SESSION"
    fi
}

scenario=${1:-}
case "$scenario" in
task1)
    start "A|$(node A)" "B|$(node B)" "C|$(node C)"
    ;;
task1-rejoin)
    start "A|$(node A)" "B (quits at 15s, rejoins at 30s)|$(node B)" "C|$(node C)"
    leave_and_rejoin clean
    ;;
task1-crash)
    start "A|$(node A)" "B (killed at 15s, rejoins at 30s)|$(node B)" "C|$(node C)"
    leave_and_rejoin crash
    ;;
task2)
    start "A|$(node A hello)" "B|$(node B hello)" "C|$(node C hello)"
    ;;
task3-loyal)
    start "CMD (loyal)|sleep 3; $(general CMD commander 2)" \
        "L1|$(general L1 lieutenant 2)" \
        "L2|$(general L2 lieutenant 2)"
    ;;
task3-traitor-cmd)
    start "CMD (TRAITOR)|sleep 3; $(general CMD commander 2 --traitor)" \
        "L1|$(general L1 lieutenant 2)" \
        "L2|$(general L2 lieutenant 2)"
    ;;
task3-traitor-lieut)
    start "CMD (loyal)|sleep 3; $(general CMD commander 2)" \
        "L1|$(general L1 lieutenant 2)" \
        "L2 (TRAITOR)|$(general L2 lieutenant 2 --traitor)"
    ;;
task4-loyal)
    start "CMD (loyal)|sleep 3; $(general CMD commander 3)" \
        "L1|$(general L1 lieutenant 3)" \
        "L2|$(general L2 lieutenant 3)" \
        "L3|$(general L3 lieutenant 3)"
    ;;
task4-traitor-cmd)
    start "CMD (TRAITOR)|sleep 3; $(general CMD commander 3 --traitor)" \
        "L1|$(general L1 lieutenant 3)" \
        "L2|$(general L2 lieutenant 3)" \
        "L3|$(general L3 lieutenant 3)"
    ;;
task4-traitor-lieut)
    start "CMD (loyal)|sleep 3; $(general CMD commander 3)" \
        "L1|$(general L1 lieutenant 3)" \
        "L2|$(general L2 lieutenant 3)" \
        "L3 (TRAITOR)|$(general L3 lieutenant 3 --traitor)"
    ;;
*)
    usage
    ;;
esac

show
