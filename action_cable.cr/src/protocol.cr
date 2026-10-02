# Wire-protocol constants, captured 1:1 from actioncable 8.1.4
# (oracle/expected.yml: proto_* cases; source: ActionCable::INTERNAL).
require "json"

module ActionCable
  # Value that can travel through a cable envelope (message payload).
  # JSON::Any covers decoded broadcast/stream payloads.
  alias CableValue = String | Int32 | Int64 | Float64 | Bool | Nil | JSON::Any | Array(CableValue) | Hash(String | Symbol, CableValue)

  module Internal
    MESSAGE_TYPES = {
      :welcome      => "welcome",
      :disconnect   => "disconnect",
      :ping         => "ping",
      :confirmation => "confirm_subscription",
      :rejection    => "reject_subscription",
    } of Symbol => String

    DISCONNECT_REASONS = {
      :unauthorized     => "unauthorized",
      :invalid_request  => "invalid_request",
      :server_restart   => "server_restart",
      :remote           => "remote",
    } of Symbol => String

    DEFAULT_MOUNT_PATH = "/cable"

    PROTOCOLS = ["actioncable-v1-json", "actioncable-unsupported"] of String

    # Ruby exposes these as one heterogeneous hash (ActionCable::INTERNAL);
    # Crystal's type system keeps them as named constants instead.
    def self.message_types : Hash(Symbol, String)
      MESSAGE_TYPES
    end

    def self.disconnect_reasons : Hash(Symbol, String)
      DISCONNECT_REASONS
    end

    def self.default_mount_path : String
      DEFAULT_MOUNT_PATH
    end

    def self.protocols : Array(String)
      PROTOCOLS
    end
  end
end
