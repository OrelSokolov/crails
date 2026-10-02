# ActionMailer::Base — DSL port (P0): default from:, mail(to:/subject:/body:)
# with a format collector (format.text/format.html), attachments[],
# headers[], class-level action methods → MessageDelivery (lazy), and
# the :test delivery method (Base.deliveries).

require "./mail"

module ActionMailer
  VERSION = "0.1.0"

  # Compile-time registry of mailer classes (for the generated
  # class-level action methods below).
  MAILERS = [] of Nil

  # Lazy delivery proxy — the explicit facade Rails builds with
  # method_missing; we enumerate the used methods instead.
  class MessageDelivery
    @cached : Mail::Message?

    def initialize(@mailer_name : String, @action : String,
                   @args : Array(ActiveJob::ArgValue),
                   @builder : Proc(Mail::Message))
    end

    def message : Mail::Message
      @cached ||= @builder.call
    end

    def deliver_now : Mail::Message
      msg = message
      Base.deliver(msg)
      msg
    end

    # Enqueues a MailDeliveryJob instead of delivering (Rails 8.1
    # argument shape, queue :mailers).
    def deliver_later(*, wait : Time::Span? = nil) : ActiveJob::Base?
      params = {} of String | Symbol => ActiveJob::ArgValue
      params["args"] = @args
      params["_aj_ruby2_keywords"] = ["args"].map(&.as(ActiveJob::ArgValue))
      job = MailDeliveryJob.set(wait: wait)
      job.perform_later(@mailer_name, @action, "deliver_now", params)
    end
  end

  # format.text { "..." } / format.html { "..." } collector passed to
  # the mail(...) block.
  class FormatCollector
    getter text_bodies = [] of String
    getter html_bodies = [] of String

    def text(&block : -> String) : Nil
      text_bodies << block.call
    end

    def html(&block : -> String) : Nil
      html_bodies << block.call
    end
  end

  # attachments["x.txt"] = {mime_type: ..., content: ...}
  class AttachmentsProxy
    getter entries = [] of {String, String, String} # filename, mime, content

    def []=(filename : String, spec : Hash(String, String)) : Nil
      entries << {filename,
                  spec["mime_type"]? || "application/octet-stream",
                  spec["content"]? || ""}
    end

    def attach(filename : String, mime_type : String, content : String) : Nil
      entries << {filename, mime_type, content}
    end

    def empty? : Bool
      entries.empty?
    end
  end

  class HeadersProxy
    getter entries = {} of String => String

    def []=(name : String, value : String) : Nil
      entries[name] = value
    end
  end

  class Base
    class_property deliveries = [] of Mail::Message
    class_property? perform_deliveries = true

    def self.deliver(msg : Mail::Message) : Nil
      deliveries << msg if perform_deliveries?
    end

    getter attachments_proxy = AttachmentsProxy.new
    getter headers_proxy = HeadersProxy.new
    getter __message : Mail::Message?

    macro inherited
      {% ::ActionMailer::MAILERS << @type %}
    end

    # default from: "..." — P0 covers :from only.
    macro default(**opts)
      {% if opts[:from] %}
        def __default_from : String
          {{ opts[:from] }}
        end
      {% end %}
    end

    def __default_from : String?
      nil
    end

    # Overridden per-subclass by end-of-program codegen (below).
    def self.__deliver(action : String, args : Array(ActiveJob::ArgValue)) : Mail::Message
      raise ArgumentError.new("Unknown mailer action: #{action}")
    end

    def attachments : AttachmentsProxy
      @attachments_proxy
    end

    def headers : HeadersProxy
      @headers_proxy
    end

    def mail(to : String? = nil, subject : String? = nil, body : String? = nil) : Mail::Message
      mail(to: to, subject: subject, body: body) { |_| }
    end

    def mail(to : String? = nil, subject : String? = nil,
             body : String? = nil, &block : FormatCollector -> Nil) : Mail::Message
      msg = Mail::Message.new
      msg.from = __default_from
      msg.to = to
      msg.subject = subject
      headers_proxy.entries.each { |k, v| msg[k] = v }

      collector = FormatCollector.new
      yield collector

      # Assemble the message shape the way ActionMailer+mail do:
      #   0 formats + body: → single text/plain
      #   1 format          → single part of that type
      #   2 formats         → multipart/alternative
      #   + attachments     → wrapped in multipart/mixed
      collector.text_bodies.each { |b| msg.add_part("text/plain", b) }
      collector.html_bodies.each { |b| msg.add_part("text/html", b) }

      if msg.parts.empty?
        msg.set_single_body(body || "", "text/plain")
      elsif msg.parts.size == 1
        msg.set_single_body(msg.parts.first.decoded, msg.parts.first.mime_type)
      else
        msg.set_multipart("multipart/alternative")
      end

      attachments_proxy.entries.each do |filename, mime, content|
        msg.add_attachment(filename, mime, content)
      end
      unless attachments_proxy.empty?
        msg.set_multipart("multipart/mixed")
      end

      @__message = msg
      msg
    end
  end
end

# End-of-program codegen: for every mailer class, each public instance
# method (the "actions") gets a class-level twin returning a lazy
# MessageDelivery — the analog of Rails' class-level method_missing —
# plus a serialized-args dispatcher (`__deliver`) used by
# MailDeliveryJob, and a name lookup (`ActionMailer.lookup_mailer`).
macro finished
  {% for m in ::ActionMailer::MAILERS %}
    class {{ m.id }}
      {% for meth in m.methods %}
        {% if meth.visibility != :private && meth.visibility != :protected && meth.name.stringify != "initialize" && !meth.name.stringify.starts_with?("__") && meth.name.stringify != "attachments" && meth.name.stringify != "headers" && meth.name.stringify != "mail" %}
          def self.{{ meth.name.id }}({{ meth.args.splat }})
            mailer = new
            delivery_args = [ {% for a in meth.args %}ActiveJob::Serialization.to_arg({{ a.name.id }}), {% end %} ] of ActiveJob::ArgValue
            builder = -> : Mail::Message do
              mailer.{{ meth.name.id }}({% for a in meth.args %}{{ a.name.id }}, {% end %})
              mailer.__message.not_nil!
            end
            ::ActionMailer::MessageDelivery.new({{ m.name.stringify }}, {{ meth.name.stringify }}, delivery_args, builder)
          end
        {% end %}
      {% end %}

      def self.__deliver(action : String, args : Array(ActiveJob::ArgValue)) : Mail::Message
        mailer = new
        {% for meth in m.methods %}
          {% if meth.visibility != :private && meth.visibility != :protected && meth.name.stringify != "initialize" && !meth.name.stringify.starts_with?("__") && meth.name.stringify != "attachments" && meth.name.stringify != "headers" && meth.name.stringify != "mail" %}
            {% arg_count = meth.args.size %}
            if action == {{ meth.name.stringify }} && args.size == {{ arg_count }}
              mailer.{{ meth.name.id }}(
                {% i = 0 %}
                {% for a in meth.args %}
                  {% if a.restriction %}
                    args[{{ i }}].as({{ a.restriction }}),
                  {% else %}
                    args[{{ i }}],
                  {% end %}
                  {% i += 1 %}
                {% end %}
              )
              return mailer.__message.not_nil!
            end
          {% end %}
        {% end %}
        raise ArgumentError.new("Unknown mailer action: #{action}")
      end
    end
  {% end %}

  def ActionMailer.lookup_mailer(name : String)
    {% for m in ::ActionMailer::MAILERS %}
      return {{ m.id }} if name == {{ m.name.stringify }}
    {% end %}
    nil
  end
end
