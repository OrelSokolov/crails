# crails_sse — 402-sse bench: ActionController::Live over HTTP::Server
# (SSE/token-streaming, chunked, disconnect-cancellation, backpressure).
# Серверная сторона; клиент — src/client.cr (общий для CRails и Rails).
#
# Эндпоинты:
#   GET /events?n=1000&d=1  — SSE-поток из n «токенов» (d мс задержки
#                              ПЕРЕД первым токеном — first-token latency)
#   GET /chunked?n=100000   — chunked-поток writeln
#   GET /infinite           — вечный SSE-тикер (для disconnect-storm)
#   GET /stats              — active/cancelled/rss_kb (мониторинг шторма)

require "json"
require "atomic"
require "action_pack_cr"

ACTIVE = Atomic(Int32).new(0)
CANCELLED = Atomic(Int32).new(0)
SERVED = Atomic(Int64).new(0)

class BenchController < ActionController::Base
  include ActionController::Live

  private def q(name : String, default : Int32) : Int32
    URI::Params.parse(request.query || "")[name]?.try(&.to_i) || default
  end

  def events
    n = q("n", 1000)
    delay = q("d", 0)
    response.headers["Content-Type"] = "text/event-stream"
    sse = ActionController::Live::SSE.new(response.stream)
    sleep delay.milliseconds if delay > 0
    n.times { |i| sse.write("token#{i} ") }
    SERVED.add(n.to_i64)
  ensure
    sse.try(&.close)
  end

  def chunked
    n = q("n", 100_000)
    response.headers["Content-Type"] = "text/plain"
    n.times { |i| response.stream.writeln "chunk-#{i} xxxxxxxxxxxxxxxxxxxx" }
    SERVED.add(n.to_i64)
  ensure
    response.stream.close
  end

  def infinite
    response.headers["Content-Type"] = "text/event-stream"
    ACTIVE.add(1)
    loop do
      response.stream.writeln "tick"
      sleep 5.milliseconds
    end
  rescue ex : ActionController::Live::ClientDisconnected
    CANCELLED.add(1)
  ensure
    ACTIVE.sub(1)
    response.stream.close
  end

  def stats
    rss = File.read("/proc/self/status").match(/VmRSS:\s+(\d+) kB/).try(&.[1].to_i) || 0
    render plain: "active=#{ACTIVE.get} cancelled=#{CANCELLED.get} " \
                  "served=#{SERVED.get} rss_kb=#{rss}"
  end
end

HOST = ENV["HOST"]? || "127.0.0.1"
PORT = (ENV["PORT"]? || "4200").to_i

server = HTTP::Server.new do |context|
  controller = BenchController.new(context)
  case context.request.path
  when "/events"   then controller.__run_action("events")
  when "/chunked"  then controller.__run_action("chunked")
  when "/infinite" then controller.__run_action("infinite")
  when "/stats"    then controller.__run_action("stats")
  else
    context.response.status_code = 404
  end
end

address = server.bind_tcp(HOST, PORT)
puts "listening on #{address}"
server.listen
