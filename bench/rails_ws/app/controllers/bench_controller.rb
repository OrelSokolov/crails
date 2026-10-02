class BenchController < ApplicationController
  skip_before_action :verify_authenticity_token

  def broadcast
    n = params[:n].to_i
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    n.times { |i| ActionCable.server.broadcast("bench", {i: i}) }
    elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000
    render json: {broadcast: n, elapsed_ms: elapsed.round(2)}
  end

  def health
    render json: {ok: true}
  end
end
