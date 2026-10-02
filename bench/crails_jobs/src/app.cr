# crails_jobs — 200-jobs bench app: ActiveJob async adapter (fiber
# pool) behind two HTTP endpoints. Job is a no-op: we measure pure
# queue overhead (enqueue → perform), not business work.

require "http/server"
require "json"
require "active_job_cr"

class NoopJob < ActiveJob::Base
  class_property latencies = [] of Int64 # ms, enqueue→perform

  def perform(enqueued_at_ms)
    NoopJob.latencies << Time.utc.to_unix_ms - enqueued_at_ms.as(Int64)
    nil
  end
end

POOL  = (ENV["POOL"]? || "16").to_i
QUEUE = (ENV["QUEUE"]? || "4096").to_i
ADAPTER = ActiveJob::AsyncAdapter.new(pool_size: POOL, queue_size: QUEUE)
ActiveJob.adapter = ADAPTER

ENQUEUED_AT = Atomic(Int64).new(0)

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
    n.times { |i| NoopJob.perform_later(now) }
    ENQUEUED_AT.add(n)
    context.response.print({"enqueued" => n}.to_json)
  when {"GET", "/drain"}
    ADAPTER.wait_empty
    context.response.print(stats_payload)
  when {"GET", "/reset"}
    NoopJob.latencies.clear
    context.response.print({"reset" => true}.to_json)
  when {"GET", "/health"}
    context.response.print({"ok" => true}.to_json)
  else
    context.response.status_code = 404
  end
  context.response.content_type = "application/json"
end

address = server.bind_tcp("127.0.0.1", (ENV["PORT"]? || "3100").to_i)
puts "crails_jobs (pool=#{POOL}, queue=#{QUEUE}) on #{address}"
server.listen
