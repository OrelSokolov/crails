# Server: pubsub owner + broadcast entry point + HTTP mount for /cable.
#
# The mount performs the WebSocket upgrade itself (instead of using
# HTTP::WebSocketHandler) so the connection layer keeps a direct handle
# on the socket IO — required by the cork-buffer fast path (P1.5).

require "http/server"
require "http/web_socket"
require "./connection"

module ActionCable
  class Server
    getter pubsub : SubscriptionAdapter::Base
    getter mount_path : String

    def initialize(@pubsub : SubscriptionAdapter::Base = SubscriptionAdapter::Async.new,
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

    # Builds an HTTP handler mounting the cable endpoint at #mount_path;
    # non-cable and non-upgrade requests pass through. Mount like:
    #
    #   server = ActionCable::Server.new
    #   HTTP::Server.new([server.ws_handler]) # combined with app routes
    #
    def ws_handler : CableHandler
      CableHandler.new(self, mount_path)
    end

    class CableHandler
      include HTTP::Handler

      def initialize(@server : Server, @mount_path : String)
      end

      def call(context : HTTP::Server::Context) : Nil
        request = context.request
        unless request.path == @mount_path && upgrade_request?(request)
          return call_next(context)
        end

        response = context.response
        version = request.headers["Sec-WebSocket-Version"]?
        unless version == HTTP::WebSocket::Protocol::VERSION
          response.status = :upgrade_required
          response.headers["Sec-WebSocket-Version"] = HTTP::WebSocket::Protocol::VERSION
          return
        end

        key = request.headers["Sec-WebSocket-Key"]?
        unless key
          response.status = :bad_request
          return
        end

        response.status = :switching_protocols
        response.headers["Upgrade"] = "websocket"
        response.headers["Connection"] = "Upgrade"
        response.headers["Sec-WebSocket-Accept"] = HTTP::WebSocket::Protocol.key_challenge(key)
        response.upgrade do |io|
          Connection.new(io, @server).run
        end
      end

      private def upgrade_request?(request) : Bool
        return false unless upgrade = request.headers["Upgrade"]?
        return false unless upgrade.compare("websocket", case_insensitive: true) == 0

        request.headers.includes_word?("Connection", "Upgrade")
      end
    end
  end
end
