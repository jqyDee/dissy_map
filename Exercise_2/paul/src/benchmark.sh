#!/bin/bash
# Usage: ./benchmark.sh <node_a_pub> <node_a_priv> <node_b_pub> <node_b_priv> <redis_priv>
# Get IPs from: terraform output

KEY=~/.ssh/labsuser.pem
NODE_A_PUB=$1
NODE_A_PRIV=$2
NODE_B_PUB=$3
NODE_B_PRIV=$4
REDIS_IP=$5

SSH="ssh -i $KEY -o StrictHostKeyChecking=no"

echo "=== Task 1 - Replicated Counter ==="

$SSH ec2-user@$NODE_A_PUB \
    "python3 -u ~/counter_1_1.py --id A --port 5001 --peer-ip $NODE_B_PRIV --peer-port 5002 --delay 0" \
    > /tmp/t1_a.log 2>&1 &

$SSH ec2-user@$NODE_B_PUB \
    "python3 -u ~/counter_1_1.py --id B --port 5002 --peer-ip $NODE_A_PRIV --peer-port 5001 --delay 0" \
    > /tmp/t1_b.log 2>&1 &

wait

grep -E "Done:|Sync" /tmp/t1_a.log | sed 's/^/  Node A: /'
grep -E "Done:|Sync" /tmp/t1_b.log | sed 's/^/  Node B: /'

echo ""
echo "=== Task 2 - Single-copy Counter (Redis) ==="

$SSH ec2-user@$NODE_A_PUB \
    "python3 -u ~/counter_2.py --id A --redis-ip $REDIS_IP --n 100 --delay 0" \
    > /tmp/t2_a.log 2>&1 &

$SSH ec2-user@$NODE_B_PUB \
    "python3 -u ~/counter_2.py --id B --redis-ip $REDIS_IP --n 100 --delay 0" \
    > /tmp/t2_b.log 2>&1 &

wait

grep -E "Done:|final" /tmp/t2_a.log | sed 's/^/  Node A: /'
grep -E "Done:|final" /tmp/t2_b.log | sed 's/^/  Node B: /'
