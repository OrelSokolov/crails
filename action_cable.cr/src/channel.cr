# ActionCable::Channel::Base — mirrors actioncable 8.1.4 channel
# semantics verified by oracle/expected.yml:
#   * transmit wraps the payload in {identifier:, message:}
#   * unsubscribe_from_channel clears streams before #unsubscribed
#   * perform_action dispatches to public subclass methods by name
#
# Deviations from the Ruby API (Crystal type system or port scope):
#   * transmit is public (Ruby keeps it private; no `send` in Crystal)
#   * streams exposed via #stream_names (Ruby: private #streams)
#   * subscription confirmation/rejection messages are sent by the
#     connection layer in 8.1 — the channel never transmits them, so
#     they are out of scope until the connection layer lands (P0.5)

module ActionCable
  # Compile-time registry of channel classes, filled via `inherited`.
  CHANNELS = [] of Nil

  # Seam implemented by the real connection layer (P0.5) and by test
  # fakes — the same identifiers/transmit/pubsub surface the gem's
  # own unit tests rely on.
  module ConnectionAPI
    abstract def identifiers : Array(Symbol)
    abstract def transmit(cable : Hash(String | Symbol, CableValue)) : Nil
    abstract def pubsub : SubscriptionAdapter::Base

    # Fast-path seam (P1.5): only reached when the pubsub adapter
    # advertises fast_broadcasts? — implemented by the real connection.
    def subscribe_stream(stream : String, identifier : String) : Nil
      raise NotImplementedError.new("subscribe_stream requires the WS connection layer")
    end

    def unsubscribe_stream(stream : String) : Nil
      raise NotImplementedError.new("unsubscribe_stream requires the WS connection layer")
    end
  end

  module Channel
    class Base
      getter connection : ConnectionAPI
      getter identifier : String
      getter params : Hash(String, String)
      getter? unsubscribed = false

      @streams = {} of String => Proc(String, Nil)
      @fast_streams = [] of String
      @subscription_rejected = false

      def initialize(@connection : ConnectionAPI, @identifier : String,
                     @params : Hash(String, String) = {} of String => String)
      end

      macro inherited
        {% ::ActionCable::CHANNELS << @type %}
      end

      # Override in subclasses — set up streams here.
      def subscribed : Nil
      end

      # Override in subclasses — cleanup here.
      def unsubscribed : Nil
      end

      def subscribe_to_channel : Nil
        subscribed
      end

      def unsubscribe_from_channel : Nil
        @unsubscribed = true
        stop_all_streams
        unsubscribed
      end

      def stream_from(broadcasting : String, callback : Proc(String, Nil)? = nil) : Nil
        # Fast path (P1.5): a transmit-only subscription registers
        # (connection, identifier) with the adapter so a broadcast can
        # encode the envelope once and fan out prebuilt bytes.
        if callback.nil? && connection.pubsub.fast_broadcasts?
          @fast_streams << broadcasting
          connection.subscribe_stream(broadcasting, @identifier)
        else
          cb = callback || default_stream_callback
          @streams[broadcasting] = cb
          connection.pubsub.subscribe(broadcasting, cb)
        end
      end

      def stop_all_streams : Nil
        @streams.each do |name, cb|
          connection.pubsub.unsubscribe(name, cb)
        end
        @streams.clear
        @fast_streams.each do |name|
          connection.unsubscribe_stream(name)
        end
        @fast_streams.clear
      end

      # Probe surface for the private Ruby #streams hash (name → callback).
      def stream_names : Array(String)
        @streams.keys + @fast_streams
      end

      def transmit(data : CableValue) : Nil
        envelope = {} of String | Symbol => CableValue
        envelope[:identifier] = @identifier
        envelope[:message] = data
        connection.transmit(envelope)
      end

      def reject : Nil
        @subscription_rejected = true
      end

      def rejected? : Bool
        @subscription_rejected
      end

      private def default_stream_callback : Proc(String, Nil)
        ->(msg : String) do
          payload = begin
            JSON.parse(msg)
          rescue
            JSON::Any.new(msg)
          end
          transmit(payload)
        end
      end

      def perform_action(data : Hash(String, String)) : Nil
        action = data["action"]?
        return unless action
        __dispatch_action(action, data)
      end

      # Overridden per-subclass by end-of-program codegen (below).
      def __dispatch_action(action : String, data : Hash(String, String)) : Bool
        false
      end
    end
  end
end

# End-of-program codegen: per-subclass action dispatch (methods are
# only known once the whole class body is parsed). A public 0-or-1-arg
# method — minus lifecycle callbacks — becomes an action, mirroring
# Ruby's action_methods + public_send(arity check).
macro finished
  {% for c in ::ActionCable::CHANNELS %}
    class {{ c.id }}
      def __dispatch_action(action : String, data : Hash(String, String)) : Bool
        {% for m in c.methods %}
          {% if m.visibility != :private && m.visibility != :protected && m.name.stringify != "subscribed" && m.name.stringify != "unsubscribed" && m.name.stringify != "initialize" %}
            {% if m.args.size == 1 %}
              if action == {{ m.name.stringify }}
                {{ m.name.id }}(data)
                return true
              end
            {% elsif m.args.size == 0 %}
              if action == {{ m.name.stringify }}
                {{ m.name.id }}
                return true
              end
            {% end %}
          {% end %}
        {% end %}
        false
      end
    end
  {% end %}

  # Channel-class lookup by name (Ruby uses const_get; we generate the
  # table at end-of-program when all channel classes are known).
  def ActionCable.lookup_channel(name : String)
    {% for c in ::ActionCable::CHANNELS %}
      return {{ c.id }} if name == {{ c.name.stringify }}
    {% end %}
    nil
  end
end
