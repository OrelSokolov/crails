#!/bin/bash
# 202-pubsub bench: CRails pubsub adapters — PG LISTEN/NOTIFY vs Redis.
# Usage: ./bench.sh [subs] [msgs]
set -e
cd "$(dirname "$0")"

SUBS=${1:-10}
MSGS=${2:-10000}

export PATH=~/crystal/crystal-1.21.0-1/bin:$PATH
[ -x bin/app ] || (mkdir -p bin && crystal build --release -o bin/app src/app.cr)

psql -U root -d postgres -c "DROP DATABASE IF EXISTS crails_bench_pubsub" >/dev/null 2>&1 || \
  sudo -u postgres psql -c "DROP DATABASE IF EXISTS crails_bench_pubsub" >/dev/null
psql -U root -d postgres -c "CREATE DATABASE crails_bench_pubsub" >/dev/null 2>&1 || \
  sudo -u postgres psql -c "CREATE DATABASE crails_bench_pubsub" >/dev/null
redis-cli -n 13 flushdb >/dev/null

for adapter in pg redis; do
  for run in 1 2 3; do
    ADAPTER=$adapter SUBS=$SUBS MSGS=$MSGS ./bin/app
  done | sort | sed -n 2p
done
