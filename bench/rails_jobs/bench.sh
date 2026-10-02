#!/bin/bash
# 200-jobs bench, Rails reference. QUEUE_ADAPTER=async (default) or sidekiq.
# App must already be running on $PORT (see run notes in ../results/200-jobs.md).
# Usage: ./bench.sh [port]
set -e
cd "$(dirname "$0")"

PORT=${1:-3200}

rss_kb() {
  # sum master + workers
  pgrep -f "puma.*:$PORT" 2>/dev/null | while read pid; do awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null; done | awk '{s+=$1} END{print s+0}'
}

echo "# rails_jobs adapter=$(grep QUEUE_ADAPTER /proc/$(pgrep -f "puma.*:$PORT" | head -1)/environ 2>/dev/null | tr '\0' '\n' | grep QUEUE_ADAPTER || echo async) (median of 3)"
printf "%-10s %-12s %-10s %-10s %-10s %-10s\n" jobs jobs_sec avg_ms p99_ms max_ms rss_kb
for n in 10000 50000 100000; do
  for run in 1 2 3; do
    curl -s localhost:$PORT/reset >/dev/null
    t0=$(date +%s%N)
    curl -s -X POST "localhost:$PORT/enqueue?n=$n" >/dev/null
    curl -s localhost:$PORT/drain > /tmp/rails_drain_$run.json
    t1=$(date +%s%N)
    sec_ms=$(( (t1 - t0) / 1000000 ))
    jobs_sec=$(( n * 1000 / (sec_ms == 0 ? 1 : sec_ms) ))
    stats=$(cat /tmp/rails_drain_$run.json | tr -d '{}"' | tr ',' ' ' | tr ':' '=')
    eval $stats
    printf "%-10s %-12s %-10s %-10s %-10s %-10s\n" \
      $n $jobs_sec $avg_ms $p99_ms $max_ms $(rss_kb)
    sleep 0.2
  done
done
