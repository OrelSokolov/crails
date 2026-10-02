# Oracle cases for ActionCable (Iteration 4).
#
# Run against the ORIGINAL gem:
#   ruby oracle/cases.rb > oracle/expected.yml
#
# Each line: "<case_id>\t<value>". The same case IDs are mirrored 1:1
# in spec/oracle_spec.cr; the Crystal port must reproduce expected.yml
# exactly (captured from actioncable 8.1.4).
#
# Channel behavior is exercised through a minimal fake connection
# (the gem's own unit-test seam: identifiers/transmit/server/config/
# pubsub). Note: subscription confirmations in 8.1 are sent by the
# CONNECTION layer, not the channel — so channel-level transmissions
# stay empty here; the wire protocol is covered by the INTERNAL
# constant cases below.
gem "actioncable", "= 8.1.4"
gem "activesupport", "= 8.1.4"
gem "actionpack", "= 8.1.4"
gem "rack", "~> 3"
gem "nio4r"
gem "concurrent-ruby"
gem "websocket-driver"
gem "rackup"
require "action_cable"
require "active_support/core_ext/hash/indifferent_access"
require "logger"
require "json"

ActionCable.server.config.cable = {"adapter" => "test"}
ActionCable.server.config.logger = Logger.new(File::NULL)

def render(v)
  case v
  when String then v
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

SERVER = ActionCable::Server::Base.new
SERVER.config.cable = {"adapter" => "test"}

class FakeConnection
  attr_reader :identifiers, :transmissions

  def initialize
    @identifiers = [:current_user]
    @transmissions = []
  end

  def transmit(cable); @transmissions << cable; end
  def server; SERVER; end
  def config; SERVER.config; end
  def pubsub; SERVER.pubsub; end
  def logger; ActiveSupport::Logger.new(File::NULL); end
  def env; {}; end
end

LOG = []

class ChatChannel < ActionCable::Channel::Base
  def subscribed
    stream_from "chat_#{params[:room]}"
    LOG << "subscribed:#{params[:room]}"
  end

  def unsubscribed
    LOG << "unsubscribed"
  end

  def speak(data)
    LOG << "speak:#{data["message"]}"
  end
end

CONN = FakeConnection.new
# Real subscription flow passes ActiveSupport::JSON.decode(identifier)
#   .with_indifferent_access (connection/subscriptions.rb#add)
CH = ChatChannel.new(CONN, "{id: 1}", {"room" => "general"}.with_indifferent_access)

# --- channel ------------------------------------------------------
case_run("ch_identifier") { CH.identifier }
case_run("ch_params")     { CH.params }
case_run("ch_subscribe_callbacks") do
  CH.subscribe_to_channel
  LOG.dup
end
case_run("ch_streams") { CH.send(:streams).keys }
case_run("ch_perform_action") do
  CH.perform_action({"action" => "speak", "message" => "hi"})
  LOG.dup
end
case_run("ch_transmit") do
  # Channel#transmit is private in 8.1 — the connection layer calls it
  CH.send(:transmit, {"hello" => "world"})
  CONN.transmissions.dup
end
case_run("ch_broadcast_recorded") do
  SERVER.pubsub.broadcast("chat_general", {"a" => 1}.to_json)
  SERVER.pubsub.broadcasts("chat_general")
end
case_run("ch_unsubscribe") do
  CH.unsubscribe_from_channel
  LOG.dup
end
case_run("ch_streams_after_unsubscribe") do
  CH.send(:streams).keys
end

# --- wire protocol constants (public, protocol-stable) -------------
case_run("proto_message_types") { ActionCable::INTERNAL[:message_types] }
case_run("proto_disconnect_reasons") { ActionCable::INTERNAL[:disconnect_reasons] }
case_run("proto_default_mount_path") { ActionCable::INTERNAL[:default_mount_path] }
case_run("proto_protocols") { ActionCable::INTERNAL[:protocols] }
