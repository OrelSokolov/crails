# action_cable_cr — Crystal port of actioncable 8.1.4 (Iteration 4, P0:
# channels + pubsub + protocol; connection/WS layer is P0.5).
require "json"
require "./protocol"
require "./subscription_adapter"
require "./channel"
require "./connection"
require "./server"
require "./ruby_inspect"

module ActionCable
  VERSION = "0.1.0"
end
