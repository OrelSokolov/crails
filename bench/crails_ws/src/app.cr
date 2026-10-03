# crails_ws — 300-websockets bench server: ActionCable-compatible /cable
# endpoint plus a broadcast trigger. Clients subscribe to BenchChannel
# (stream "bench"); POST /broadcast?n=N fires N broadcasts immediately.
# Delivery rides the fast path (P1.5): default stream_from registers a
# transmit-only subscription; the adapter encodes the envelope once per
# broadcast and CorkWriter batches writes.

require "http/server"
require "json"
require "action_cable_cr"

class BenchChannel < ActionCable::Channel::Base
  def subscribed : Nil
    stream_from "bench"
  end
end

CABLE = ActionCable::Server.new
WS = CABLE.ws_handler

server = HTTP::Server.new do |context|
  if context.request.path == "/cable"
    WS.call(context)
    next
  end
  case {context.request.method, context.request.path}
  when {"POST", "/broadcast"}
    n = (context.request.query_params["n"]? || "100").to_i
    t0 = Time.monotonic
    n.times { |i| CABLE.broadcast("bench", %q({"i":) + i.to_s + "}") }
    elapsed = (Time.monotonic - t0).total_milliseconds
    context.response.print({"broadcast" => n, "elapsed_ms" => elapsed.round(2)}.to_json)
  when {"GET", "/stats"}
    context.response.print({"ok" => true}.to_json)
  when {"GET", "/health"}
    context.response.print({"ok" => true}.to_json)
  else
    context.response.status_code = 404
  end
  context.response.content_type = "application/json"
end

address = server.bind_tcp("127.0.0.1", (ENV["PORT"]? || "3300").to_i)
puts "crails_ws on #{address} (cable at /cable)"
server.listen
