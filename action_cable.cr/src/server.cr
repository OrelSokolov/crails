# Server: pubsub owner + broadcast entry point + HTTP mount for /cable.

module ActionCable
  class Server
    getter pubsub : SubscriptionAdapter::Base
    getter mount_path : String

    def initialize(@pubsub : SubscriptionAdapter::Base = SubscriptionAdapter::Test.new,
                   @mount_path : String = Internal::DEFAULT_MOUNT_PATH)
    end

    def broadcast(stream_name : String, message : String) : Nil
      pubsub.broadcast(stream_name, message)
    end

    def broadcast(stream_name : String, message) : Nil
      broadcast(stream_name, message.to_json)
    end

    def shutdown : Nil
      pubsub.shutdown
    end

    # Builds an HTTP::WebSocketHandler mounting the cable endpoint at
    # #mount_path; pass-through for anything else. Mount like:
    #
    #   server = ActionCable::Server.new
    #   HTTP::Server.new([server.ws_handler]) # combined with app routes
    #
    def ws_handler : HTTP::WebSocketHandler
      cable = self
      HTTP::WebSocketHandler.new do |ws, context|
        if context.request.path == cable.mount_path
          Connection.new(ws, cable).run
        end
      end
    end
  end
end

require "http/web_socket"
require "./connection"
