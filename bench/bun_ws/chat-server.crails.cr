# chat-server.crails.cr — same chat server as chat-server.cr, but the
# fan-out rides action_cable_cr's fast-path machinery (CorkWriter):
# the outgoing frame is encoded once per message and the same bytes go
# to every connection (Bun publishText analog); each socket gets one
# batched write per flush cycle.

require "http/server"
require "http/web_socket"
require "../../action_cable.cr/src/action_cable_cr"

CLIENTS_TO_WAIT_FOR = (ENV["CLIENTS_COUNT"]? || "32").to_i
PORT = (ENV["PORT"]? || "4001").to_i

class ChatConn
  getter writer : ActionCable::CorkWriter
  getter name : String

  def initialize(@io : IO, @name : String)
    @iolock = Mutex.new
    @writer = ActionCable::CorkWriter.new(@io, @iolock)
    @ws = HTTP::WebSocket.new(ActionCable::LockedImageIO.new(@io, @iolock), sync_close: false)
  end

  def on_message(&block : String -> Nil) : Nil
    @ws.on_message { |msg| block.call(msg) }
  end

  def run : Nil
    @ws.run
  ensure
    @writer.close
  end
end

CONNS = [] of ChatConn
CONNS_LOCK = Mutex.new

def broadcast(text : String) : Nil
  frame = ActionCable::CorkWriter.text_frame(text)
  CONNS_LOCK.synchronize do
    CONNS.each &.writer.deliver_frame(frame)
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
      conn = ChatConn.new(io, name)

      conn.on_message do |msg|
        broadcast("#{name}: #{msg}")
      end

      CONNS_LOCK.synchronize { CONNS << conn }
      puts "#{name} connected (#{CLIENTS_TO_WAIT_FOR - CONNS.size} remain)"

      if CONNS.size == CLIENTS_TO_WAIT_FOR
        puts "All clients connected"
        spawn do
          sleep 100.milliseconds
          puts %(Starting benchmark by sending "ready" message)
          broadcast("ready")
        end
      end

      conn.run
      CONNS_LOCK.synchronize { CONNS.delete(conn) }
    end
    next
  end
  context.response.status_code = 404
end

address = server.bind_tcp("0.0.0.0", PORT)
puts "chat-server.crails on #{address}, waiting for #{CLIENTS_TO_WAIT_FOR} clients..."
server.listen
