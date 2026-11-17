#!/usr/bin/env bash
set -e

VMS="zk node1 node2 node3 node4 node5"

# Launch VM $1 with RAM $2, unless it already exists
# multipass info succeeds when vm already exists -> multipass launch isnt executed
launch() {
  multipass info "$1" >/dev/null 2>&1 || multipass launch 24.04 --name "$1" --memory "$2"
}

# Launch all 6 VMs in parallel (& = background), then wait for all of them
launch zk 1G &
for i in 1 2 3 4 5; do
  launch node$i 512M &
done
for job in $(jobs -p); do wait "$job"; done   # propagates failures to set -e

# Restart stopped VMs (no-op for running ones)
multipass start $VMS

# ZooKeeper
until multipass exec zk -- true 2>/dev/null; do sleep 2; done
multipass exec zk -- sudo apt-get update
multipass exec zk -- sudo apt-get install -y zookeeperd

# Make "zk" resolvable on every node -> nodes use --zk zk:2181, no IP needed
ZK_IP=$(multipass info zk --format csv | awk -F, 'NR==2 {print $5}')
for i in 1 2 3 4 5; do
  multipass exec node$i -- sudo sh -c "sed -i '/ zk\$/d' /etc/hosts && echo '$ZK_IP zk' >> /etc/hosts"
done

multipass list
echo "ZooKeeper: $ZK_IP:2181  (on nodes: --zk zk:2181)"
