#!/bin/bash
# 203-jobs bench: Kiq (sidekiq-wire-compatible Redis queue) — enqueue +
# drain through one process with WORKERS processor fibers. Median of 3.
set -e
cd "$(dirname "$0")"

WORKERS=${1:-8}
PORT=3107

export PATH=~/crystal/crystal-1.21.0-1/bin:$PATH
[ -x bin/app ] || (mkdir -p bin && crystal build --release -o bin/app src/app.cr)

redis-cli -n 13 flushdb >/dev/null

WORKERS=$WORKERS PORT=$PORT ./bin/app &>/tmp/kiq_bench.log &
APP_PID=$!
trap "kill $APP_PID 2>/dev/null" EXIT
sleep 1

echo "# crails_kiq workers=$WORKERS (median of 3)"
printf "%-8s %-11s %-11s %-9s %-8s %-8s %-8s\n" jobs enq_sec drain_sec jobs_sec avg_ms p99_ms rss_kb
for n in 10000 50000; do
  for run in 1 2 3; do
    curl -s localhost:$PORT/reset >/dev/null
    e0=$(date +%s%N)
    curl -s -X POST "localhost:$PORT/enqueue?n=$n" >/dev/null
    e1=$(date +%s%N)
    drain=$(curl -s -X POST "localhost:$PORT/drain?n=$n")
    d1=$(date +%s%N)
    echo "$((e1-e0))|$((d1-e1))|$drain"
  done | sort -t'|' -k2 -n | sed -n 2p | {
    IFS='|' read enq_ns drain_ns drain
    enq_s=$(( 1000000000 * n / enq_ns ))
    drain_s=$(( 1000000000 * n / drain_ns ))
    rss=$(awk '/VmRSS/{print $2}' /proc/$APP_PID/status)
    printf "%-8s %-11s %-11s %-9s %-8s %-8s %-8s\n" "$n" "$enq_s" "$drain_s" \
      "$(( n * 1000 / ( (enq_ns + drain_ns) / 1000000 ) ))" \
      "$(echo $drain | jq -r .avg_ms)" "$(echo $drain | jq -r .p99_ms)" "$rss"
  }
done
kill $APP_PID 2>/dev/null
