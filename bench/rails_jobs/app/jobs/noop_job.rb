# No-op job: measures pure queue overhead (enqueue → perform).
class NoopJob < ApplicationJob
  def perform(enqueued_at_ms)
    BenchStats.record(enqueued_at_ms)
  end
end
