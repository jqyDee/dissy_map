#!/usr/bin/env bash
# Delete each VM separately, so missing ones don't block the rest
for vm in zk node1 node2 node3 node4 node5; do
  multipass delete --purge "$vm" 2>/dev/null && echo "deleted $vm"
done
multipass list
