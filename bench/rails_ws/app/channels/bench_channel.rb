class BenchChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "bench"
  end
end
