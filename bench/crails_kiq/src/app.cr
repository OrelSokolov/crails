# crails_kiq — 203-jobs bench: the Kiq queue (sidekiq-wire-compatible
# Redis queue) behind HTTP endpoints. Job is a no-op: pure queue
# overhead (LPUSH/BRPOP + payload JSON round-trip), like
# bench/crails_solidqueue. WORKERS processor fibers in one process.

require "http/server"
require "json"
require "kiq_cr"

WORKERS = (ENV["WORKERS"]? || "8").to_i

class NoopKiqJob
  include Kiq::Job
  kiq_options queue: "default", retry: false

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

  def perform(*args)
    enq_ms = args.first?.try(&.to_s.to_i64) || Time.utc.to_unix_ms
    LATENCIES << Time.utc.to_unix_ms - enq_ms
    PERFORMED.add(1)
    nil
  end
end

CFG = Kiq.default_configuration
CFG.redis = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/13")
CFG.concurrency = WORKERS
CFG.logger = ::Log.for("Kiq", :error)

def stats_payload : String
  lats = NoopKiqJob.latencies.sort!
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

# One long-lived launcher: WORKERS processor fibers + the scheduled
# poller (keeps the topology of a real sidekiq process).
LAUNCHER = Kiq::Launcher.new(CFG, ["default"], concurrency: WORKERS, strict: true)
LAUNCHER.run

server = HTTP::Server.new do |context|
  case {context.request.method, context.request.path}
  when {"POST", "/enqueue"}
    n = (context.request.query_params["n"]? || "1000").to_i
    now = Time.utc.to_unix_ms
    n.times { NoopKiqJob.perform_async(now) }
    context.response.print({"enqueued" => n}.to_json)
  when {"POST", "/drain"}
    target = (context.request.query_params["n"]? || "0").to_i
    # wait until every enqueued job has been performed and the queue is empty
    deadline = Time.utc.to_unix_f + 120
    while (NoopKiqJob.performed.get < target ||
           CFG.redis_client.llen("queue:default") > 0) && Time.utc.to_unix_f < deadline
      Fiber.yield
      sleep(0.001.seconds)
    end
    context.response.print(stats_payload)
  when {"GET", "/reset"}
    NoopKiqJob.latencies.clear
    NoopKiqJob.performed.set(0)
    CFG.redis_client.flushdb
    context.response.print({"reset" => true}.to_json)
  when {"GET", "/health"}
    context.response.print({"ok" => "kiq"}.to_json)
  else
    context.response.status_code = 404
  end
  context.response.content_type = "application/json"
end

port = (ENV["PORT"]? || "3107").to_i
puts "listening on #{port} (kiq, workers=#{WORKERS})"
server.listen(port)
