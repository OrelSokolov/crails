# crails_pubsub — 202-pubsub bench: cross-process pubsub throughput
# (broadcast → subscriber delivery) through the ActionCable
# SubscriptionAdapter port. ADAPTER=pg (LISTEN/NOTIFY) or redis.
# Standalone binary (no HTTP): subscribe S callbacks to a channel,
# broadcast M messages, report delivered msg/s per subscriber.

require "json"
require "atomic"
require "action_cable_cr"
require "action_cable_cr/adapters/pg_pubsub"
require "action_cable_cr/adapters/redis_pubsub"

ADAPTER_NAME = ENV.fetch("ADAPTER", "pg")
SUBS = (ENV["SUBS"]? || "10").to_i
MSGS = (ENV["MSGS"]? || "10000").to_i
PAYLOAD = ENV.fetch("PAYLOAD", "{\"identifier\":\"stream\",\"data\":\"{\\\"x\\\":1}\"}")

ADAPTER = if ADAPTER_NAME == "pg"
  ActionCable::SubscriptionAdapter::PostgreSQL.connect(
    ENV.fetch("DATABASE_URL", "postgres:///crails_bench_pubsub"))
else
  ActionCable::SubscriptionAdapter::Redis.new(
    url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/13"))
end

delivered = Atomic(Int64).new(0)

SUBS.times do
  ADAPTER.subscribe("bench-stream", ->(payload : String) { delivered.add(1); nil })
end
sleep 0.5 # let subscriptions settle

t0 = Time.monotonic
MSGS.times { ADAPTER.broadcast("bench-stream", PAYLOAD) }
enqueue_done = Time.monotonic

# wait for deliveries: every broadcast must reach every subscriber
deadline = enqueue_done + 30.seconds
while delivered.get < MSGS * SUBS && Time.monotonic < deadline
  sleep 0.01
end
t1 = Time.monotonic

broadcast_ms = (enqueue_done - t0).total_milliseconds.round(2)
total_ms = (t1 - t0).total_milliseconds.round(2)
puts({
  "adapter"    => ADAPTER_NAME,
  "subs"       => SUBS,
  "msgs"       => MSGS,
  "payload_b"  => PAYLOAD.bytesize,
  "broadcasts_per_s" => (MSGS / (enqueue_done - t0).total_seconds).round(2),
  "broadcast_ms_total" => broadcast_ms,
  "delivered"  => delivered.get,
  "deliveries_per_s" => (delivered.get / (t1 - t0).total_seconds).round(2),
  "wall_ms"    => total_ms,
}.to_json)

ADAPTER.shutdown
