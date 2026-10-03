# chat-server.cr — Crystal port of oven-sh/bun bench/websocket-server
# (same protocol: client connects to /?name=X, server echoes "name: msg"
# to every client; "ready" broadcast after all clients connected).
#
# MODE=frame (default): build the outgoing text frame once per message
#   and write the same bytes to every socket — the analog of Bun's
#   publishText (encode once, fan out).
# MODE=send: per-connection ws.send() — the analog of Bun's send() /
#   Node "ws" broadcast loop.

require "http/server"
require "http/web_socket"

CLIENTS_TO_WAIT_FOR = (ENV["CLIENTS_COUNT"]? || "32").to_i
PORT = (ENV["PORT"]? || "4001").to_i
MODE = ENV["MODE"]? || "frame"

class Conn
  getter io : IO
  getter name : String
  getter ws : HTTP::WebSocket

  def initialize(@io : IO, @name : String, @ws : HTTP::WebSocket)
  end
end

CONNS = [] of Conn

# Server->client frames are never masked, so one pre-encoded frame can be
# written to every socket verbatim.
def text_frame(payload : String) : Bytes
  data = payload.to_slice
  header = IO::Memory.new
  header.write_byte(0x81_u8) # FIN + text opcode
  len = data.size
  if len < 126
    header.write_byte(len.to_u8)
  elsif len <= 65535
    header.write_byte(126_u8)
    header.write_bytes(len.to_u16, IO::ByteFormat::BigEndian)
  else
    header.write_byte(127_u8)
    header.write_bytes(len.to_u64, IO::ByteFormat::BigEndian)
  end
  frame = Bytes.new(header.size + len)
  header.to_slice.copy_to(frame)
  data.copy_to(frame + header.size)
  frame
end

def broadcast(text : String) : Nil
  if MODE == "frame"
    frame = text_frame(text)
    CONNS.each do |c|
      c.io.write(frame)
      c.io.flush
    end
  else
    CONNS.each &.ws.send(text)
  end
end

server = HTTP::Server.new do |context|
  req = context.request
  upgrade = req.headers.get?("Upgrade").try(&.first?).try(&.downcase)
  if upgrade == "websocket"
    key = req.headers["Sec-WebSocket-Key"]
    resp = context.response
    resp.status_code = 101
    resp.headers["Upgrade"] = "websocket"
    resp.headers["Connection"] = "Upgrade"
    resp.headers["Sec-WebSocket-Accept"] = HTTP::WebSocket::Protocol.key_challenge(key)
    name = req.query_params["name"]? || "Client #?"

    resp.upgrade do |io|
      ws = HTTP::WebSocket.new(io)
      conn = Conn.new(io, name, ws)

      ws.on_message do |msg|
        broadcast("#{name}: #{msg}")
      end

      CONNS << conn
      puts "#{name} connected (#{CLIENTS_TO_WAIT_FOR - CONNS.size} remain)"

      if CONNS.size == CLIENTS_TO_WAIT_FOR
        puts "All clients connected"
        spawn do
          sleep 100.milliseconds
          puts %(Starting benchmark by sending "ready" message)
          broadcast("ready")
        end
      end

      ws.run
      CONNS.delete(conn)
    end
    next
  end
  context.response.status_code = 404
end

address = server.bind_tcp("0.0.0.0", PORT)
puts "chat-server.cr (mode=#{MODE}) on #{address}, waiting for #{CLIENTS_TO_WAIT_FOR} clients..."
server.listen
