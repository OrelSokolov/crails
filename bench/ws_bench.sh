#!/bin/bash
# 300-websockets bench: N fiber clients hold connections, subscribe,
# then a burst of B broadcasts; measures delivery rate and losses.
# Usage: ./ws_bench.sh <port> <server_pid_file> [label]
set -e
cd "$(dirname "$0")/loadgen"

PORT=${1:?port}
PIDFILE=${2:?pid file}
LABEL=${3:-port$PORT}
CLIENTS=${CLIENTS:-300}
N=${N:-100}
export PATH=~/crystal/crystal-1.21.0-1/bin:$PATH

crystal build --release -o /tmp/ws_load_bin ws_load.cr

echo "# $LABEL clients=$CLIENTS burst=$N (median of 3)"
for run in 1 2 3; do
  /tmp/ws_load_bin --host 127.0.0.1 --port $PORT --clients $CLIENTS --n $N
  sleep 0.3
done

# RSS window: hold connections for 6s while we sample.
SRV_PID=$(cat $PIDFILE)
( /tmp/ws_load_bin --host 127.0.0.1 --port $PORT --clients $CLIENTS --n 1 --hold 6 &>/dev/null ) &
HOLDER=$!
sleep 3
RSS=$(awk '/VmRSS/{print $2}' /proc/$SRV_PID/status)
CONNS=$(ss -t state established "( sport = :$PORT )" 2>/dev/null | tail -n +2 | wc -l)
echo "# rss_kb=$RSS established_conns=$CONNS clients=$CLIENTS"
wait $HOLDER
