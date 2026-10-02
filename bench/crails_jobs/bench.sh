#!/bin/bash
# 200-jobs bench: CRails async adapter (in-process fiber pool).
# Usage: ./bench.sh [pool_size] (default 16). 3 runs per load, median.
set -e
cd "$(dirname "$0")"

POOL=${1:-16}
PORT=3100
OUT=/tmp/crails_jobs_bench.log

export PATH=~/crystal/crystal-1.21.0-1/bin:$PATH
[ -x bin/jobs_app ] || crystal build --release -o bin/jobs_app src/app.cr

POOL=$POOL PORT=$PORT ./bin/jobs_app &>$OUT &
APP_PID=$!
trap "kill $APP_PID 2>/dev/null" EXIT
sleep 0.5

rss_kb() { awk '/VmRSS/{print $2}' /proc/$APP_PID/status; }

echo "# crails_jobs pool=$POOL (median of 3)"
printf "%-10s %-12s %-10s %-10s %-10s %-10s %-8s\n" jobs jobs_sec avg_ms p99_ms max_ms rss_kb pool
for n in 10000 50000 100000; do
  for run in 1 2 3; do
    curl -s localhost:$PORT/reset >/dev/null
    t0=$(date +%s%N)
    curl -s -X POST "localhost:$PORT/enqueue?n=$n" >/dev/null
    curl -s localhost:$PORT/drain > /tmp/drain_$run.json
    t1=$(date +%s%N)
    sec=$(( (t1 - t0) / 10000000 )); sec_ms=$(( (t1 - t0) / 1000000 ))
    jobs_sec=$(( n * 1000 / (sec_ms == 0 ? 1 : sec_ms) ))
    stats=$(cat /tmp/drain_$run.json | tr -d '{}"' | tr ',' ' ' | tr ':' '=')
    eval $stats
    printf "%-10s %-12s %-10s %-10s %-10s %-10s %-8s\n" \
      $n $jobs_sec $avg_ms $p99_ms $max_ms $(rss_kb) $POOL
    sleep 0.2
  done
done
