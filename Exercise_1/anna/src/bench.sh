#!/usr/bin/env bash

HOST=${1:-localhost}

for SIZE in 300 1000 2000 3000; do
    for RUN in 1 2 3 4 5; do
    echo "size=$SIZE run=$RUN"
    time curl -s -o /dev/null -X POST "http://$HOST:8000/api/render-bitmap?size=$SIZE" \
  -H "Content-Type: application/json" \
  -d '{"board":["X","O","X","O","X","O","O","X","X"],"winner":"X"}'
    done
done