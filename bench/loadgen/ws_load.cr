# ws_load — WebSocket load generator for the 300-websockets bench.
# Crystal fiber clients: connect, subscribe, hold, count deliveries.
#
# Usage:
#   crystal run --release ws_load.cr -- --host 127.0.0.1 --port 3300 \
#       --clients 300 --n 100 [--path /cable]
#
# Protocol expectation is the Rails ActionCable JSON one, so the same
# generator works against both CRails and Rails ActionCable.

require "http/web_socket"
require "json"
require "option_parser"

host = "127.0.0.1"
port = 3300
clients_n = 300
n = 100
path = "/cable"
hold = 0.0

OptionParser.parse do |o|
  o.on("--host H", "server host") { |v| host = v }
  o.on("--port P", "server port") { |v| port = v.to_i }
  o.on("--clients C", "number of ws clients") { |v| clients_n = v.to_i }
  o.on("--n N", "broadcasts per burst") { |v| n = v.to_i }
  o.on("--path S", "cable path") { |v| path = v }
  o.on("--hold SECS", "hold connections before burst (RSS window)") { |v| hold = v.to_f }
end

delivered = Atomic(Int64).new(0)
connected = Atomic(Int64).new(0)
subscribed = Atomic(Int64).new(0)

done = Channel(Nil).new

clients_n.times do
  spawn do
    # Browsers always send Origin; Rails ActionCable rejects requests
    # without one, so the generator must behave like a real client.
    headers = HTTP::Headers{"Origin" => "http://localhost:#{port}"}
    ws = HTTP::WebSocket.new(host, path, port, headers: headers)
    identifier = %q({"channel":"BenchChannel"})

    ws.on_message do |msg|
      data = JSON.parse(msg)
      case data["type"]?
      when "welcome"
        ws.send({"command" => "subscribe", "identifier" => identifier}.to_json)
      when "confirm_subscription"
        subscribed.add(1)
      when nil
        delivered.add(1) if data["message"]?
      end
    end

    ws.on_close do
      done.send(nil)
    end

    begin
      ws.run
    rescue
    end
  end
end

# Wait for all subscriptions to settle (welcome + confirm handshake).
t0 = Time.monotonic
while subscribed.get < clients_n
  raise "only #{subscribed.get}/#{clients_n} subscribed" if (Time.monotonic - t0) > 30.seconds
  Fiber.yield
  sleep 0.01.milliseconds
end
connect_secs = (Time.monotonic - t0).total_seconds

# Optional RSS window: connections stay up while an external observer
# reads the server's /proc/<pid>/status.
sleep hold if hold > 0

# Snapshot deliveries before the broadcast burst.
before = delivered.get

t0 = Time.monotonic
HTTP::Client.post("http://#{host}:#{port}/broadcast?n=#{n}")
burst_deadline = t0 + 30.seconds
expected = clients_n.to_i64 * n

# Wait until every client got every message (or timeout).
while delivered.get - before < expected
  raise "delivery timeout: got #{delivered.get - before}/#{expected}" if Time.monotonic > burst_deadline
  Fiber.yield
  sleep 0.1.milliseconds
end
burst_secs = (Time.monotonic - t0).total_seconds

got = delivered.get - before
msg_per_sec = (got / burst_secs).round(0)
puts({clients: clients_n, subscribed: subscribed.get, msgs_expected: expected,
      msgs_delivered: got, burst_secs: burst_secs.round(3),
      msgs_per_sec: msg_per_sec, handshake_secs: connect_secs.round(3)}.to_json)
exit(0)
