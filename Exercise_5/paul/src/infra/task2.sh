#!/usr/bin/env bash
# Task 2: concurrent operations through different nodes.
# reset deletes /auction -> interactive REPL nodes lose their membership entry (restart them afterwards).
#
# multipass exec quirks:
#   </dev/null : don't hand the terminal to multipass exec (background & jobs reading it would be suspended)
#   never redirect multipass exec's own output to /dev/null -> it hangs; redirect inside the VM instead

ZKCLI=/usr/share/zookeeper/bin/zkCli.sh

# run <node> <id> <command...> : one-shot auction command on a node
run() {
  # shift 2: removes first two arguments, eg "node1 a" "node2 b" so only eg "bid alice 150" remains
  local node=$1 id=$2; shift 2
  multipass exec "$node" -- /home/ubuntu/auction --zk zk:2181 --id "$id" "$@" </dev/null
}

# Fresh auction: delete old state, start with one bid of 100
reset() {
  # we let deleteall run inside the zk vm inside its zkCli.sh, the zookeepers command-line client
  # deleteall removes all znodes recursively
  multipass exec zk -- sh -c "$ZKCLI -server localhost:2181 deleteall /auction >/dev/null 2>&1" </dev/null
  run node3 seed bid seed 100
}

echo "== 1) two competing bids"
reset
run node1 a bid alice 150 &
run node2 b bid bob 140 &
wait
run node3 q query

echo "== 2) bid while another node closes"
reset
run node1 a bid alice 200 &
run node2 c close &
wait
run node3 q query
