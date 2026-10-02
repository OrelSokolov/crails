# Latency/throughput accounting shared by both adapters.
# async: in-process array under a mutex (jobs run in Puma's process).
# sidekiq: jobs run in a separate process, so counters live in Redis.
class BenchStats
  SIDEKIQ = ENV.fetch("QUEUE_ADAPTER", "async") == "sidekiq"
  REDIS_URL = ENV.fetch("REDIS_URL", "redis://127.0.0.1:6379/0")

  DONE_KEY = "jobs:done"
  LAT_KEY = "jobs:lat"

  class << self
    def record(enqueued_at_ms)
      lat = (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).to_i - enqueued_at_ms
      if SIDEKIQ
        redis.pipelined do |p|
          p.incr(DONE_KEY)
          p.rpush(LAT_KEY, lat)
        end
      else
        instance.record_local(lat)
      end
    end

    def performed
      if SIDEKIQ
        redis.get(DONE_KEY).to_i
      else
        instance.local_size
      end
    end

    def reset
      if SIDEKIQ
        redis.del(DONE_KEY, LAT_KEY)
      else
        instance.local_reset
      end
    end

    # {performed:, avg_ms:, p99_ms:, max_ms:}
    def stats
      lats = if SIDEKIQ
        redis.lrange(LAT_KEY, 0, -1).map!(&:to_i)
      else
        instance.local_latencies
      end.sort

      n = lats.size
      return {performed: 0, avg_ms: 0.0, p99_ms: 0, max_ms: 0} if n.zero?

      {
        performed: n,
        avg_ms: (lats.sum.to_f / n).round(2),
        p99_ms: lats[(n * 0.99).to_i.clamp(0, n - 1)],
        max_ms: lats.last,
      }
    end

    private

    def redis
      @redis ||= Redis.new(url: REDIS_URL)
    end

    def instance
      @instance ||= new
    end
  end

  def initialize
    @mutex = Mutex.new
    @latencies = []
  end

  def record_local(lat)
    @mutex.synchronize { @latencies << lat }
  end

  def local_size
    @mutex.synchronize { @latencies.size }
  end

  def local_reset
    @mutex.synchronize { @latencies.clear }
  end

  def local_latencies
    @mutex.synchronize { @latencies.dup }
  end
end
