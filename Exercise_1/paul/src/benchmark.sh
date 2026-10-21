#!/bin/bash

URL="http://localhost:8000/api/render-bitmap"
PAYLOAD='{"board":["X","O"," ","X","O"," ","X"," "," "],"winner":"X"}'

# Workload levels (number of total requests)
WORKLOADS=(10 50 100 200)

echo "=== Benchmarking Endpoint Throughput ==="
echo "Workload (N Requests) | Execution Time"

for COUNT in "${WORKLOADS[@]}"; do
  echo -n "N = $COUNT requests: "
  
  # Time the total duration of sending N requests sequentially
  /usr/bin/time -f "Real: %Es | CPU User: %Us | System: %Ss" \
    bash -c "for ((i=1; i<=$COUNT; i++)); do
      curl -s -X POST '$URL' \
        -H 'Content-Type: application/json' \
        -d '$PAYLOAD' \
        -o /dev/null
    done"
done