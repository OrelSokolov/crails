#!/bin/bash
# 401-turbo-streams bench: Turbo Streams broadcast pipeline —
# turbo-stream tag render + Async-pubsub fanout.
# Usage: ./bench.sh [subs] [msgs]
set -e
cd "$(dirname "$0")"

SUBS=${1:-10}
MSGS=${2:-10000}

export PATH=~/crystal/crystal-1.21.0-1/bin:$PATH
[ -x bin/app ] || (mkdir -p bin && crystal build --release -o bin/app src/app.cr)

for run in 1 2 3; do
  SUBS=$SUBS MSGS=$MSGS ./bin/app
done
