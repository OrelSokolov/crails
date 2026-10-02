class BenchController < ApplicationController
  # No CSRF for API-style bench endpoints.
  skip_before_action :verify_authenticity_token

  @@enqueued = 0

  def enqueue
    n = params[:n].to_i
    now = (Process.clock_gettime(Process::CLOCK_REALTIME) * 1000).to_i
    n.times { NoopJob.perform_later(now) }
    @@enqueued += n
    render json: {enqueued: n}
  end

  def drain
    target = @@enqueued
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 300
    while BenchStats.performed < target
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        return render json: {error: "drain timeout", performed: BenchStats.performed, target: target}
      end
      sleep 0.005
    end
    render json: BenchStats.stats
  end

  def reset
    BenchStats.reset
    @@enqueued = 0
    render json: {reset: true}
  end

  def health
    render json: {ok: true}
  end
end
