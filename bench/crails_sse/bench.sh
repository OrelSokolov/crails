#!/bin/bash
# 402-sse bench: SSE/chunked-стриминг — ActionController::Live на CRails
# (fiber на соединение) vs actionpack 8.1.4 + Puma 6.6.1 (threads).
# Матрица: fanout (конкуррентные SSE-стримы), chunked-throughput,
# first-token latency, disconnect-storm (отмена fiber'а vs MRI-thread),
# RSS. Результаты сводятся в bench/results/402-sse.md.
set -e
cd "$(dirname "$0")"

export PATH=~/crystal/crystal-1.21.0-1/bin:$PATH
CLIENT=bin/client

[ -x bin/server ] || (mkdir -p bin && crystal build --release -o bin/server src/server.cr)
[ -x $CLIENT ] || crystal build --release -o $CLIENT src/client.cr

run_matrix () {
  local name=$1 host=$2 port=$3
  echo "--- $name (http://$host:$port) ---"
  $CLIENT fanout  $host $port 50 2000
  $CLIENT fanout  $host $port 50 2000
  $CLIENT chunked $host $port 100000
  $CLIENT chunked $host $port 100000
  $CLIENT first   $host $port 200
  [ -x bin/storm ] || crystal build --release -o bin/storm src/storm.cr
  ./bin/storm   $host $port 200
}

echo "=== CRails (ActionController::Live port) ==="
PORT=4200 ./bin/server &
CPID=$!
sleep 0.5
run_matrix crails 127.0.0.1 4200
kill $CPID 2>/dev/null || true
wait $CPID 2>/dev/null || true

echo
echo "=== Rails 8.1.4 + Puma 6.6.1 ==="
(cd ../rails_sse && PORT=4300 ruby server.rb > /tmp/rails_sse.log 2>&1) &
RPID=$!
sleep 2
run_matrix rails 127.0.0.1 4300
kill $RPID 2>/dev/null || true
pkill -f "ruby server.rb" 2>/dev/null || true
