# crails_solidqueue — 201-jobs bench: durable ActiveJob queues behind
# HTTP endpoints. ADAPTER=pg (SolidQueue adapter, PG) or redis
# (RedisQueueAdapter). Job is a no-op: pure queue overhead
# (enqueue → claim → perform), like bench/crails_jobs.

require "http/server"
require "json"
require "active_job_cr"
require "active_job_cr/solid_queue"
require "active_job_cr/adapters/redis_queue"

ADAPTER_NAME = ENV.fetch("ADAPTER", "pg")
WORKERS = (ENV["WORKERS"]? || "8").to_i

class NoopJob < ActiveJob::Base
  # NOTE: counters are constants — Crystal's class_property getter hands
  # out a fresh instance for Atomic/Array mutation-through-getter.
  LATENCIES = [] of Int64
  PERFORMED = Atomic(Int64).new(0)

  def self.performed : Atomic(Int64)
    PERFORMED
  end

  def self.latencies : Array(Int64)
    LATENCIES
  end

  def perform(enqueued_at_ms)
    LATENCIES << Time.utc.to_unix_ms - enqueued_at_ms.as(Int64)
    PERFORMED.add(1)
    nil
  end
end

ADAPTER = if ADAPTER_NAME == "pg"
  a = ActiveJob::SolidQueue::Adapter.connect(
    ENV.fetch("DATABASE_URL", "postgres:///crails_bench_sq"))
  a.clear
  a
else
  a = ActiveJob::RedisQueueAdapter.new(
    url: ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/13"))
  a.clear
  a
end

ActiveJob.adapter = ADAPTER

def stats_payload : String
  lats = NoopJob.latencies.sort!
  n = lats.size
  avg = n == 0 ? 0.0 : lats.sum.to_f / n
  p99 = n == 0 ? 0 : lats[(n * 0.99).to_i.clamp(0, n - 1)]
  max = n == 0 ? 0 : lats.last
  {
    "performed" => n,
    "avg_ms"    => (avg * 100).round / 100,
    "p99_ms"    => p99,
    "max_ms"    => max,
  }.to_json
end

server = HTTP::Server.new do |context|
  case {context.request.method, context.request.path}
  when {"POST", "/enqueue"}
    n = (context.request.query_params["n"]? || "1000").to_i
    now = Time.utc.to_unix_ms
    n.times { NoopJob.perform_later(now) }
    context.response.print({"enqueued" => n}.to_json)
  when {"POST", "/drain"}
    target = context.request.query_params["n"]?.try(&.to_i) ||
             NoopJob.performed.get + ADAPTER.pending_count
    stop = Channel(Nil).new
    WORKERS.times { spawn { ADAPTER.work(["default"], 50, 0.005.seconds, stop) } }
    # wait until every enqueued job has been performed
    while NoopJob.performed.get < target || ADAPTER.pending_count > 0
      Fiber.yield
      sleep 0.001
    end
    stop.close
    context.response.print(stats_payload)
  when {"GET", "/reset"}
    NoopJob.latencies.clear
    NoopJob.performed.set(0)
    ADAPTER.clear
    context.response.print({"reset" => true}.to_json)
  when {"GET", "/health"}
    context.response.print({"ok" => ADAPTER_NAME}.to_json)
  else
    context.response.status_code = 404
  end
  context.response.content_type = "application/json"
end

port = (ENV["PORT"]? || "3105").to_i
puts "listening on #{port} (#{ADAPTER_NAME})"
server.listen(port)
