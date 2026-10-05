# crails_turbo — 401-turbo-streams bench: Turbo Streams broadcast path —
# turbo-stream tag render (ActionHelper.action_tag) + fanout через
# cable-сервер (Async-адаптер) подписчикам. Standalone (без HTTP):
# подписываем S колбэков на стрим, делаем M broadcast_action_to
# (prepend с контентом — рендер тега на каждой итерации), считаем
# broadcasts/s и deliveries/s.
#
# Плюс isolированная проба рендера тега (без доставки) — render/s.

require "json"
require "atomic"
require "turbo_cr"

SUBS = (ENV["SUBS"]? || "10").to_i
MSGS = (ENV["MSGS"]? || "10000").to_i

Turbo.signed_stream_verifier_key = "bench-key-bench-key-bench-key-bench-key!!"
CABLE = ActionCable::Server.new # Async pubsub, как дефолт Rails-демо
Turbo.cable_server = CABLE

STREAM = "bench-stream"
delivered = Atomic(Int64).new(0)

SUBS.times do
  CABLE.pubsub.subscribe(STREAM, ->(payload : String) { delivered.add(1); nil })
end
sleep 0.5 # пусть подписки осядут

# --- 1) полный цикл: рендер тега + доставка S подписчикам ------------------
delivered.set(0)
t1 = Time.monotonic
MSGS.times do
  Turbo::StreamsChannel.broadcast_action_to([STREAM], :prepend,
    target: "list", content: "<div class=\"card\">hello turbo</div>", render: false)
end
t2 = Time.monotonic

deadline = t2 + 30.seconds
while delivered.get < MSGS * SUBS && Time.monotonic < deadline
  sleep 0.01
end
t3 = Time.monotonic

# --- 2) изолированный рендер (без broadcast) --------------------------------
N_RENDER = 200_000
one = -> do
  Turbo::Streams::ActionHelper.action_tag(:prepend, target: "list",
    template: "<div class=\"card\">hello turbo</div>")
end
t4 = Time.monotonic
N_RENDER.times { one.call }
t5 = Time.monotonic

puts({
  "subs"                => SUBS,
  "msgs"                => MSGS,
  "renders_per_s"       => (N_RENDER / (t5 - t4).total_seconds).round(2),
  "broadcasts_per_s"    => (MSGS / (t2 - t1).total_seconds).round(2),
  "delivered"           => delivered.get,
  "deliveries_per_s"    => (delivered.get / (t3 - t1).total_seconds).round(2),
  "fanout_wall_ms"      => (t3 - t1).total_milliseconds.round(2),
  "payload_b"           => one.call.to_s.bytesize,
}.to_json)

CABLE.shutdown
