# bench/crails_lv — LiveView counter bench server (live_view_cr).
#
# One CounterLive-style view (no timers — pure event/diff loop),
# mounted at /live/websocket, served by a bare HTTP::Server.

require "http/server"
require "../../live_view.cr/src/live_view_cr"

class BenchCounterLive < LiveView::Base
  @count : Int64 = 0

  def handle_event(event : String, params : JSON::Any) : Nil
    case event
    when "incr" then @count += 1
    when "decr" then @count -= 1
    end
  end

  lv_template "src/counter_live.html"
end

socket = LiveView::Socket.new("bench_secret")
server = HTTP::Server.new([socket])
address = server.bind_tcp("127.0.0.1", ARGV[0]?.try(&.to_i) || 4400)
puts "crails_lv listening on #{address}"
server.listen
