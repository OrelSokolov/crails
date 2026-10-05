# turbo.cr — порт turbo-rails 2.0.x (Turbo Streams), неймспейс `Turbo`.
#
# Оракул: oracle/cases.rb → oracle/expected.yml, снят с настоящего
# turbo-rails 2.0.20 + rails 8.1.4. Зеркало: spec/oracle_spec.cr.
#
# Отклонения от Ruby API (типизация Crystal) — в PLAN.md.

require "base64"
require "html"
require "active_support_cr"
require "action_view_cr"
require "action_pack_cr"
require "action_cable_cr"
require "active_record_cr"
require "active_job_cr"

require "./stream_name"
require "./action_helper"
require "./tag_builder"
require "./broadcasts"
require "./helpers"
require "./broadcastable"
require "./jobs"

module Turbo
  VERSION = "2.0.20-cr"

  # GlobalID-lite: имя приложения в gid://-URI (globalid-гем в Rails
  # подключается к AR railtie; здесь — минимальный аналог).
  class_property app : String = "crails"

  @@signed_stream_verifier_key : String?
  @@signed_stream_verifier : ActiveSupport::MessageVerifier?

  def self.signed_stream_verifier_key=(key : String) : Nil
    @@signed_stream_verifier_key = key
    @@signed_stream_verifier = nil
  end

  def self.signed_stream_verifier : ActiveSupport::MessageVerifier
    if (v = @@signed_stream_verifier)
      return v
    end
    key = @@signed_stream_verifier_key
    raise ArgumentError.new("Turbo requires a signed_stream_verifier_key") unless key
    @@signed_stream_verifier = ActiveSupport::MessageVerifier.new(key)
    @@signed_stream_verifier.not_nil!
  end

  # Cable-сервер для broadcast_stream_to (в Rails — ActionCable.server).
  # Приложение подменяет на свой (PG/Redis pubsub); дефолт — Async.
  @@cable_server : ActionCable::Server?
  @@default_cable_server : ActionCable::Server?

  def self.cable_server=(server : ActionCable::Server) : Nil
    @@cable_server = server
  end

  def self.cable : ActionCable::Server
    @@cable_server || (@@default_cable_server ||= ActionCable::Server.new)
  end

  # --- Типы -------------------------------------------------------------

  # Стримуемое: строки/символы (имена) и AR-записи (по GlobalID).
  alias Streamable = String | Symbol | ActiveRecord::Base
  # DOM-цель: селектор/id/запись (dom_id).
  alias DomTarget = String | Symbol | ActiveRecord::Base | Nil
  # Значение locals/assigns рендера.
  alias RenderVal = String | Int32 | Int64 | Float64 | Bool | ActiveRecord::Base

  # --- Рендер-seam (аналог ApplicationController.render) ----------------
  # Компилируемый язык не умеет рантайм-рендер по строке: приложение
  # регистрирует проки на свои compile-time скомпилированные партиалы и
  # turbo_stream-шаблоны (см. spec/oracle_spec.cr и demo).

  # partial_renderer.call(partial, locals) -> HTML
  class_property partial_renderer : Proc(String, Hash(String, RenderVal), String)?

  # template_renderer.call(template, assigns) -> HTML
  # (turbo_stream-формат, для broadcast_render_to / BroadcastJob)
  class_property template_renderer : Proc(String, Hash(String, RenderVal), String)?

  def self.render_partial(partial : String, locals : Hash(String, RenderVal)) : String
    renderer = @@partial_renderer
    raise ArgumentError.new("Turbo.partial_renderer is not configured (see turbo.cr/PLAN.md)") unless renderer
    renderer.call(partial, locals)
  end

  def self.render_template(template : String, assigns : Hash(String, RenderVal)) : String
    renderer = @@template_renderer
    raise ArgumentError.new("Turbo.template_renderer is not configured (see turbo.cr/PLAN.md)") unless renderer
    renderer.call(template, assigns)
  end

  # Рендер записи по умолчанию: партиал из to_partial_path, locals —
  # имя модели (Rails: render partial: record).
  def self.render_record(record : ActiveRecord::Base) : String?
    locals = {} of String => RenderVal
    locals[record.class.name.underscore] = record
    render_partial(record.to_partial_path, locals)
  end

  # Нормализация locals/assigns: литерал {"post" => post} выводится как
  # Hash(String, Post), а генерики инвариантны — пересобираем в
  # Hash(String, RenderVal).
  def self.cast_locals(locals : Hash?) : Hash(String, RenderVal)
    h = {} of String => RenderVal
    locals.try { |l| l.each { |k, v| h[k.to_s] = v.as(RenderVal) } }
    h
  end

  # --- Реестр Broadcastable-моделей (для _later-джобов) -----------------
  # compile-time: заполняется `include Turbo::Broadcastable`; gid-декод
  # генерируется в `macro finished` в конце этого файла.

  BROADCASTABLE_MODELS = [] of TypeNode

  # gid "Post:1" -> запись (рефетч, как GlobalID в Rails).
  def self.find_record(class_name : String, id : Int64) : ActiveRecord::Base?
    lookup_record(class_name, id)
  end

  # Перезаписывается в macro finished ниже.
  protected def self.lookup_record(class_name : String, id : Int64) : ActiveRecord::Base?
    nil
  end
end

# GlobalID-lite на ActiveRecord (зеркалит globalid-railtie):
# to_gid_param — urlsafe-b64 без padding, "gid://<app>/<Model>/<id>".
class ActiveRecord::Base
  def to_gid_param : String
    gid = "gid://#{Turbo.app}/#{self.class.name}/#{id.not_nil!}"
    Base64.urlsafe_encode(gid, padding: false)
  end

  # Rails: "posts/post" — каталог множественное, файл единственное.
  def to_partial_path : String
    singular = self.class.name.underscore
    "#{singular.pluralize}/#{singular}"
  end
end

# Хелперы turbo доступны всем контроллерам (в Rails их подмешивает
# engine); templates компилируются на классах контроллеров.
class ActionController::Base
  include Turbo::StreamsHelper
  include Turbo::FramesHelper
end

# End-of-program codegen: gid-диспетчер по реестру Broadcastable-моделей.
macro finished
  module Turbo
    protected def self.lookup_record(class_name : String, id : Int64) : ActiveRecord::Base?
      case class_name
      {% for m in Turbo::BROADCASTABLE_MODELS %}
      when {{ m.name.stringify }} then {{ m.id }}.find?(id)
      {% end %}
      else
        nil
      end
    end
  end
end
