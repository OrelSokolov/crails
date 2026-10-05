# Джобы turbo (1:1 с app/jobs/turbo/streams): ActionBroadcastJob,
# BroadcastJob, BroadcastStreamJob. Аргументы — ArgValue-совместимые;
# AR-записи в locals/assigns едут как gid-конверты {"_turbo_record" =>
# [class, id]} и рефетчатся в джобе (семантика GlobalID в Rails).

module Turbo
  # Кодирование/декодирование опций рендера для _later-джобов.
  module JobRendering
    RECORD_KEY = "_turbo_record"

    def self.encode(partial : String?, template : String?,
                    locals : Hash(String, RenderVal)?,
                    assigns : Hash(String, RenderVal)?) : Hash(String | Symbol, ActiveJob::ArgValue)
      h = {} of String | Symbol => ActiveJob::ArgValue
      h["partial"] = partial if partial
      h["template"] = template if template
      h["locals"] = encode_values(locals) if locals
      h["assigns"] = encode_values(assigns) if assigns
      h
    end

    def self.encode_values(values : Hash(String, RenderVal)) : Hash(String | Symbol, ActiveJob::ArgValue)
      h = {} of String | Symbol => ActiveJob::ArgValue
      values.each do |k, v|
        h[k] = case v
               when ActiveRecord::Base
                 envelope = {} of String | Symbol => ActiveJob::ArgValue
                 envelope["class"] = v.class.name
                 envelope["id"] = v.id.not_nil!
                 envelope
               when String, Int32, Int64, Float64, Bool then v
               else
                 raise ArgumentError.new("unsupported local #{k}: #{v.class}")
               end
      end
      h
    end

    def self.decode_values(values : ActiveJob::ArgValue?) : Hash(String, RenderVal)
      decoded = {} of String => RenderVal
      if values.is_a?(Hash)
        values.each do |k, v|
          key = k.to_s
          decoded[key] = decode_value(v)
        end
      end
      decoded
    end

    def self.decode_value(v : ActiveJob::ArgValue) : RenderVal
      case v
      when Hash
        if (klass = v["class"]?).is_a?(String) && (id = v["id"]?).is_a?(Int64)
          record = Turbo.find_record(klass, id)
          return record if record
        end
        ""
      when String, Int32, Int64, Float64, Bool then v
      else                                        ""
      end
    end
  end
end

class Turbo::Streams::ActionBroadcastJob < ActiveJob::Base
  # Аргументы — ActiveJob::ArgValue (нетипизированные, как требует
  # диспетчер порта); касты внутри. Диспетчер генерирует конструкторы
  # до 4 аргументов, поэтому target/targets/attributes/rendering едут
  # одним payload-хешем.
  def perform(stream_name, action, payload)
    p = payload.as(Hash(String | Symbol, ActiveJob::ArgValue))
    attrs = {} of String => String
    if (a = p["attributes"]?).is_a?(Hash(String | Symbol, ActiveJob::ArgValue))
      a.each { |k, v| attrs[k.to_s] = v.to_s if v.is_a?(String) }
    end
    r = (p["rendering"]?).as(Hash(String | Symbol, ActiveJob::ArgValue))

    Turbo::StreamsChannel.broadcast_action_to(
      [stream_name.as(String)], action.as(String),
      target: p["target"]?.as?(String), targets: p["targets"]?.as?(String),
      content: r["content"]?.as?(String),
      html: r["html"]?.as?(String),
      partial: r["partial"]?.as?(String),
      template: r["template"]?.as?(String),
      locals: Turbo::JobRendering.decode_values(r["locals"]?),
      assigns: Turbo::JobRendering.decode_values(r["assigns"]?),
      attributes: attrs)
  end
end

class Turbo::Streams::BroadcastJob < ActiveJob::Base
  def perform(stream_name, rendering)
    r = rendering.as(Hash(String | Symbol, ActiveJob::ArgValue))
    Turbo::StreamsChannel.broadcast_render_to(
      [stream_name.as(String)],
      template: r["template"]?.as?(String),
      assigns: Turbo::JobRendering.decode_values(r["assigns"]?))
  end
end

class Turbo::Streams::BroadcastStreamJob < ActiveJob::Base
  def perform(stream_name, content)
    Turbo.cable.broadcast(stream_name.as(String), content.as(String))
  end
end
