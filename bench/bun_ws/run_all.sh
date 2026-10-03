#!/bin/bash
# Runs the oven-sh/bun websocket-server bench against every runtime on
# this machine with one bun client (32 clients, 10 one-second samples).
# Usage: ./run_all.sh [variant ...]   (default: all)
set -u
cd "$(dirname "$0")"
BUN=~/.bun/bin/bun
PORT_BASE=${PORT_BASE:-4100}

run_variant() {
  local label=$1 start_cmd=$2 port=$3 logfile=$4 pattern=$5
  echo "=== $label (port $port) ==="
  rm -f "$logfile.server" "$logfile.client"
  bash -c "$start_cmd" &>"$logfile.server" &
  local srv=$!
  for i in $(seq 1 100); do
    (echo > /dev/tcp/127.0.0.1/$port) 2>/dev/null && break
    sleep 0.1
  done
  SERVER=ws://127.0.0.1:$port CLIENTS_COUNT=32 $BUN chat-client.mjs &>"$logfile.client"
  local peak=""
  local srvpid=$(pgrep -f "$pattern" | head -1)
  if [ -n "$srvpid" ]; then
    peak=$(awk '/VmHWM/{printf "%d MB", $2/1024}' /proc/$srvpid/status 2>/dev/null)
  fi
  kill $srv 2>/dev/null; wait $srv 2>/dev/null
  pkill -f "$pattern" 2>/dev/null
  sleep 0.5

  python3 - "$logfile.client" "$logfile.server" "$label" "$peak" <<'EOF'
import json, re, sys
client, server, label, peak = sys.argv[1:5]
runs = []
text = open(client).read()
m = re.search(r"\[\s*((?:\d+,\s*)*\d+)\s*\]", text, re.S)
if m:
    runs = [int(x) for x in m.group(1).split(",")]
if runs:
    runs_sorted = sorted(runs)
    median = runs_sorted[len(runs)//2]
    print(f"{label}\tmedian={median}\tmax={max(runs)}\tpeak_rss={peak or 'n/a'}")
    print(f"\truns={runs}")
else:
    print(f"{label}\tFAILED\tpeak_rss={peak or 'n/a'}")
    print(text[-500:])
EOF
}

VARIANTS=${@:-bun-publish bun-send node-ws crystal-frame crystal-send crails-cable}
for v in $VARIANTS; do
  case $v in
    bun-publish)   run_variant "$v" "PORT=$((PORT_BASE+1)) $BUN chat-server.bun.js" $((PORT_BASE+1)) /tmp/ws_$v "chat-server.bun.js" ;;
    bun-send)      run_variant "$v" "PORT=$((PORT_BASE+2)) $BUN chat-server.bun-send.js" $((PORT_BASE+2)) /tmp/ws_$v "chat-server.bun-send.js" ;;
    node-ws)       run_variant "$v" "PORT=$((PORT_BASE+3)) node chat-server.node.mjs" $((PORT_BASE+3)) /tmp/ws_$v "chat-server.node.mjs" ;;
    crystal-frame) run_variant "$v" "PORT=$((PORT_BASE+4)) MODE=frame ./chat-server.bin" $((PORT_BASE+4)) /tmp/ws_$v "chat-server.bin" ;;
    crystal-send)  run_variant "$v" "PORT=$((PORT_BASE+5)) MODE=send ./chat-server.bin" $((PORT_BASE+5)) /tmp/ws_$v "chat-server.bin" ;;
    crails-cable)  run_variant "$v" "PORT=$((PORT_BASE+6)) ./chat-server.crails-cable.bin" $((PORT_BASE+6)) /tmp/ws_$v "chat-server.crails-cable.bin" ;;
  esac
done
