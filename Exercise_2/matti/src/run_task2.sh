#!/usr/bin/env bash
set -euo pipefail

MODE=${1:-incr}
N=${2:-100}
SSH="ssh -i $HOME/.ssh/labsuser.pem -o StrictHostKeyChecking=accept-new"

OUT=$(terraform output -json task_2)
A=$(jq -r .nodes.A <<<"$OUT")
B=$(jq -r .nodes.B <<<"$OUT")
REDIS=$(jq -r .redis_private <<<"$OUT")

# reset the shared counter (via node A, Redis has no public IP in the output)
$SSH ec2-user@"$A" "python3 -c \"import redis; redis.Redis(host='$REDIS').set('counter', 0)\""

# both nodes start at the same moment, 5 s from now (time for SSH to connect)
START_AT=$(( $(date +%s) + 5 ))
RUN="cd app-task-2 && REDIS_HOST=$REDIS MODE=$MODE N=$N START_AT=$START_AT python3 counter_redis.py"

$SSH ec2-user@"$A" "export NODE_ID=A && $RUN" > node_A.log &
$SSH ec2-user@"$B" "export NODE_ID=B && $RUN" > node_B.log &
wait

tail -n 2 node_A.log node_B.log   # timing summary + final counter of each node
