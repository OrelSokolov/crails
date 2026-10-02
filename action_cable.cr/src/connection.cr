# Connection: fiber-per-connection cable endpoint. Speaks the Rails
# ActionCable JSON protocol 1:1 so the official @rails/actioncable
# JS client works unchanged:
#   server → client: welcome | ping | confirm_subscription |
#                     reject_subscription | {identifier, message}
#   client → server: {command: subscribe|message|unsubscribe,
#                     identifier, data?}

module ActionCable
  class Connection
    include ConnectionAPI

    PING_INTERVAL = 3.seconds

    def initialize(@ws : HTTP::WebSocket, @server : Server)
      @subscriptions = {} of String => Channel::Base
      @closed = false
    end

    def run : Nil
      @ws.on_message { |msg| handle_command(msg) }
      @ws.on_close do
        @closed = true
        @subscriptions.each_value(&.unsubscribe_from_channel)
        @subscriptions.clear
      end
      send_welcome
      spawn_ping_loop
      @ws.run # blocks this fiber until the socket closes
    end

    # --- ConnectionAPI (channel seam) --------------------------------
    def identifiers : Array(Symbol)
      [] of Symbol # identified_by lands in P1
    end

    def transmit(cable : Hash(String | Symbol, CableValue)) : Nil
      payload = {} of String => CableValue
      payload["identifier"] = cable[:identifier]? || cable["identifier"]?
      payload["message"] = cable[:message]? || cable["message"]?
      send_json(payload)
    end

    def pubsub : SubscriptionAdapter::Base
      @server.pubsub
    end

    # --- protocol ----------------------------------------------------
    private def send_welcome : Nil
      send_json({"type" => Internal::MESSAGE_TYPES[:welcome]} of String => CableValue)
    end

    private def send_confirmation(identifier : String) : Nil
      send_json({
        "identifier" => identifier,
        "type"       => Internal::MESSAGE_TYPES[:confirmation],
      } of String => CableValue)
    end

    private def send_rejection(identifier : String) : Nil
      send_json({
        "identifier" => identifier,
        "type"       => Internal::MESSAGE_TYPES[:rejection],
      } of String => CableValue)
    end

    private def spawn_ping_loop : Nil
      spawn do
        until @closed
          sleep PING_INTERVAL
          break if @closed
          send_json({
            "type"    => Internal::MESSAGE_TYPES[:ping],
            "message" => Time.utc.to_unix_ms.to_s,
          } of String => CableValue)
        end
      end
    end

    private def handle_command(raw : String) : Nil
      data = JSON.parse(raw)
      command = data["command"]?.try &.as_s
      identifier = data["identifier"]?.try &.as_s

      case command
      when "subscribe"
        return unless identifier && !@subscriptions[identifier]?
        id_options = JSON.parse(identifier)
        klass = ActionCable.lookup_channel(id_options["channel"].as_s)
        if klass
          channel = klass.new(self, identifier, string_params(id_options))
          @subscriptions[identifier] = channel
          channel.subscribe_to_channel
          send_confirmation(identifier)
        else
          send_rejection(identifier)
        end
      when "message"
        return unless identifier && (channel = @subscriptions[identifier]?)
        channel.perform_action(string_params(JSON.parse(data["data"].as_s)))
      when "unsubscribe"
        if (channel = @subscriptions.delete(identifier))
          channel.unsubscribe_from_channel
        end
      end
    rescue ex : JSON::ParseException
      # Malformed frames are dropped, connection stays alive (the gem
      # logs and rescues per-command).
    end

    private def string_params(any : JSON::Any) : Hash(String, String)
      params = {} of String => String
      any.as_h.each { |k, v| params[k] = v.to_s }
      params
    rescue
      {} of String => String
    end

    private def send_json(payload : Hash(String, CableValue)) : Nil
      return if @closed
      @ws.send(payload.to_json)
    end
  end
end
