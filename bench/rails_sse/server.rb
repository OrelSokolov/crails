# rails_sse — контраг_pointка 402-sse bench: ActionController::Live 8.1.4
# на Puma 6.6.1 (thread mode), те же эндпоинты, что у bench/crails_sse.
# Клиент общий — bench/crails_sse/src/client.cr.

gem "actionpack", "= 8.1.4"
gem "activesupport", "= 8.1.4"
gem "rack", "~> 3.2"
gem "puma", "= 6.6.1"
require "action_controller"
require "puma"
require "puma/server"

# атомарных гемов нет в этой руби — Mutex-счётчики
class Counter
  def initialize; @m = Mutex.new; @v = 0; end
  def add(n = 1); @m.synchronize { @v += n }; end
  def sub(n = 1); @m.synchronize { @v -= n }; end
  def value; @m.synchronize { @v }; end
end

ACTIVE = Counter.new
CANCELLED = Counter.new
SERVED = Counter.new

class BenchController < ActionController::Base
  include ActionController::Live

  private def q(name, default)
    (request.query_parameters[name] || default).to_i
  end

  def events
    n = q("n", 1000)
    delay = q("d", 0)
    response.headers["Content-Type"] = "text/event-stream"
    sse = ActionController::Live::SSE.new(response.stream)
    sleep(delay / 1000.0) if delay > 0
    n.times { |i| sse.write("token#{i} ") }
    SERVED.add(n)
  ensure
    sse.close
  end

  def chunked
    n = q("n", 100_000)
    response.headers["Content-Type"] = "text/plain"
    n.times { |i| response.stream.writeln "chunk-#{i} xxxxxxxxxxxxxxxxxxxx" }
    SERVED.add(n)
  ensure
    response.stream.close
  end

  def infinite
    response.headers["Content-Type"] = "text/event-stream"
    ACTIVE.add
    loop do
      response.stream.writeln "tick"
      sleep 0.005
    end
  rescue ActionController::Live::ClientDisconnected
    CANCELLED.add
  ensure
    ACTIVE.sub
    response.stream.close
  end

  def stats
    rss = File.read("/proc/self/status")[/^VmRSS:\s+(\d+) kB/, 1].to_i
    response.headers["Content-Type"] = "text/plain"
    response.write "active=#{ACTIVE.value} cancelled=#{CANCELLED.value} " \
                   "served=#{SERVED.value} rss_kb=#{rss}"
  end
end

APP = ->(env) {
  controller, action =
    case env["PATH_INFO"]
    when "/events"   then [BenchController, :events]
    when "/chunked"  then [BenchController, :chunked]
    when "/infinite" then [BenchController, :infinite]
    when "/stats"    then [BenchController, :stats]
    else [nil, nil]
    end
  if controller
    controller.action(action).call(env)
  else
    [404, { "Content-Type" => "text/plain" }, ["not found"]]
  end
}

host = ENV["HOST"] || "127.0.0.1"
port = (ENV["PORT"] || "4300").to_i
server = Puma::Server.new(APP, Puma::Events.new, max_threads: 256)
server.add_tcp_listener(host, port)
puts "listening on #{host}:#{port}"
server.run.join
