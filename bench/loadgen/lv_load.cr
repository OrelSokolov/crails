# lv_load — LiveView event-loop load generator (Phoenix Channels V2).
#
# Fiber clients: join the counter view, then closed-loop push "incr"
# events (send → wait phx_reply) and measure events/s + latency.
# The same generator runs against CRails live_view.cr and real Phoenix
# LiveView — the wire protocol is identical.
#
# Usage:
#   crystal run --release lv_load.cr -- --host 127.0.0.1 --port 4400 \
#       --clients 16 --events 20000 [--view phx-counter0]
#
# View tokens: for CRails the server signs any id with view name
# "BenchCounterLive"; pass --crails to have the generator sign a token
# locally with the bench secret. For Phoenix, paste --token directly.

require "http/web_socket"
require "json"
require "option_parser"
require "socket"
require "base64"
require "random/secure"

# Hand-rolled ws upgrade so the client socket gets TCP_NODELAY (the
# stdlib WebSocket client doesn't expose its socket; without NODELAY,
# tiny event frames hit Nagle's 40ms delayed-ACK stall).
def nodelay_ws_connect(host : String, port : Int32, path : String, cookie : String?) : HTTP::WebSocket
  sock = TCPSocket.new(host, port)
  sock.tcp_nodelay = true
  sock.sync = false

  key = Base64.strict_encode(Random::Secure.random_bytes(16))
  headers = String.build do |io|
    io << "GET #{path} HTTP/1.1\r\n"
    io << "Host: #{host}:#{port}\r\n"
    io << "Upgrade: websocket\r\nConnection: Upgrade\r\n"
    io << "Sec-WebSocket-Key: #{key}\r\nSec-WebSocket-Version: 13\r\n"
    io << "Cookie: #{cookie}\r\n" if cookie
    io << "\r\n"
  end
  sock << headers
  sock.flush

  status = sock.gets.not_nil!
  raise "upgrade failed: #{status}" unless status.includes?("101")
  while (line = sock.gets) && !line.empty?
  end

  protocol = HTTP::WebSocket::Protocol.new(sock, masked: true)
  HTTP::WebSocket.new(protocol)
end

host = "127.0.0.1"
port = 4400
clients_n = 16
events_per_client = 20_000
view = "phx-counter0"
crails = false
token : String? = nil
cookie : String? = nil

OptionParser.parse do |o|
  o.on("--host H", "server host") { |v| host = v }
  o.on("--port P", "server port") { |v| port = v.to_i }
  o.on("--clients C", "ws clients (fibers)") { |v| clients_n = v.to_i }
  o.on("--events N", "events per client") { |v| events_per_client = v.to_i }
  o.on("--view V", "view id") { |v| view = v }
  o.on("--crails", "sign the token locally (live_view_cr bench secret)") { crails = true }
  o.on("--token T", "pre-signed session token (Phoenix)") { |v| token = v }
  o.on("--cookie C", "session cookie for the ws upgrade (Phoenix)") { |v| cookie = v }
end

# Minimal local signer — mirrors LiveView::Token (base64url payload +
# HMAC-SHA256 over Digest::SHA256), only used with --crails.
require "digest/sha256"
def sign_token(secret : String, payload : String) : String
  key = secret.to_slice
  ipad = Bytes.new(64); opad = Bytes.new(64)
  64.times do |i|
    b = i < key.size ? key[i] : 0_u8
    ipad[i] = b ^ 0x36_u8; opad[i] = b ^ 0x5c_u8
  end
  inner = Digest::SHA256.digest(ipad + payload.to_slice)
  mac = Digest::SHA256.digest(opad + inner)
  Base64.urlsafe_encode(payload) + "." + Base64.urlsafe_encode(mac, padding: false)
end

session_token = token
if crails && session_token.nil?
  session_token = sign_token("bench_secret",
    %{{"id":"#{view}","view":"BenchCounterLive","session":{}}})
end
abort "need --token or --crails" unless session_token

done = Channel(NamedTuple(n: Int32, ns: Array(Float64))).new

clients_n.times do |c|
  spawn do
    latencies = Array(Float64).new(events_per_client)
    ws = nodelay_ws_connect(host, port, "/live/websocket?vsn=2.0.0", cookie)
    inbox = Channel(JSON::Any).new(128)
    ws.on_message { |m| inbox.send(JSON.parse(m)) }
    spawn { ws.run }
    Fiber.yield

    topic = "lv:#{view}"
    ws.send(%(["1","1","#{topic}","phx_join",
      {"session": #{session_token.to_json}, "params": {"_mounts": "0"},
       "url": "http://#{host}:#{port}/live"}]))
    reply = inbox.receive
    abort "join failed: #{reply}" unless reply[4]["status"]? == "ok"

    incr = %(["1","R","#{topic}","event",
      {"type": "click", "event": "incr", "value": {}}])

    events_per_client.times do |i|
      t0 = Time.monotonic
      ws.send incr.sub("R", (i + 2).to_s)
      loop do
        r = inbox.receive
        break if r[1] == JSON::Any.new((i + 2).to_s)
      end
      latencies << (Time.monotonic - t0).total_nanoseconds
    end

    done.send({n: events_per_client, ns: latencies})
    ws.close
  end
end

total_ns = 0.0
all = Array(Float64).new(clients_n * events_per_client)
started = Time.monotonic
clients_n.times { |i|
  r = done.receive
  all.concat(r[:ns])
}
elapsed = Time.monotonic - started

all.sort!
total = all.size
p50 = all[total // 2] / 1000
p99 = all[(total * 99) // 100] / 1000

printf "clients=%d events=%d elapsed=%.2fs ev/s=%.0f p50=%.1fµs p99=%.1fµs\n",
  clients_n, total, elapsed.total_seconds, total / elapsed.total_seconds, p50, p99
