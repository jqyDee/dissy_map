#!/usr/bin/env bash
set -euo pipefail

N=${1:-100}
SSH="ssh -i $HOME/.ssh/labsuser.pem -o StrictHostKeyChecking=accept-new"

OUT=$(terraform output -json task_1)
A=$(jq -r .A.public <<<"$OUT")
A_PRIVATE=$(jq -r .A.private <<<"$OUT")
B=$(jq -r .B.public <<<"$OUT")
B_PRIVATE=$(jq -r .B.private <<<"$OUT")

# both nodes start at the same moment, 5 s from now (time for SSH to connect)
START_AT=$(( $(date +%s) + 5 ))
RUN="cd app-task-1 && N=$N START_AT=$START_AT python3 counter_bench.py"

$SSH ec2-user@"$A" "export NODE_ID=A PEER=$B_PRIVATE && $RUN" > node_A.log &
$SSH ec2-user@"$B" "export NODE_ID=B PEER=$A_PRIVATE && $RUN" > node_B.log &
wait

tail -n 2 node_A.log node_B.log   # timing summary + final counter of each node