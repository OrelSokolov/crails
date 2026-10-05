# Turbo::Broadcastable — concern моделей (1:1 с app/models/concerns/
# turbo/broadcastable.rb, turbo-rails 2.0.20): broadcast_* instance-методы
# + декларативные broadcasts_to / broadcasts / broadcasts_refreshes(_to)
# через after_commit-коллбэки AR.
#
# Дефолты рендера — как extract_options_and_add_target /
# broadcast_rendering_with_defaults: locals всегда дополняются записью
# под именем модели; без html/partial/template/render:false партиал
# берётся из to_partial_path; target подставляется только если не задан
# ни target, ни targets.
#
# Отклонения (типизация): stream в broadcasts_to — Symbol (метод модели)
# или String-литерал; proc-стримы — P2.

module Turbo
  module Broadcastable
    # per-class флаг подавления броадкастов (suppressing_turbo_broadcasts)
    SUPPRESSED = {} of String => Bool

    macro included
      {% Turbo::BROADCASTABLE_MODELS << @type %}
      extend ::Turbo::Broadcastable::ClassMethods
    end

    module ClassMethods
      def broadcast_target_default : String
        self.name.underscore.pluralize
      end

      def suppressed_turbo_broadcasts? : Bool
        Turbo::Broadcastable::SUPPRESSED[self.name]? || false
      end

      def suppressing_turbo_broadcasts(&) : Nil
        key = self.name
        original = Turbo::Broadcastable::SUPPRESSED[key]? || false
        Turbo::Broadcastable::SUPPRESSED[key] = true
        begin
          yield
        ensure
          Turbo::Broadcastable::SUPPRESSED[key] = original
        end
      end
    end

    # Декларативы — макросами в теле модуля (include делает их видимыми
    # в теле класса; extend внутри macro included макросы не поднимает).

    # broadcasts_to :board, inserts_by: :prepend, target: "board_messages"
    # stream: Symbol (метод модели, вызывается на инстансе) или String.
    macro broadcasts_to(stream, inserts_by = :append, target = nil, partial = nil)
      {% stream_expr = stream.is_a?(SymbolLiteral) ? stream.id : stream %}
      {% target_expr = target.is_a?(SymbolLiteral) ? target.stringify : target %}
      after_commit(on: :create) do
        broadcast_action_later_to([{{ stream_expr }}],
          action: {{ inserts_by }}, target: {{ target_expr || "broadcast_target_default".id }},
          partial: {{ partial }})
      end
      after_commit(on: :update) do
        broadcast_replace_later_to([{{ stream_expr }}], partial: {{ partial }})
      end
      after_commit(on: :destroy) do
        broadcast_remove_to([{{ stream_expr }}])
      end
    end

    # broadcasts — стрим по умолчанию: множественное имя модели
    # (pluralize — рантайм-инфлектор, в макро-мире его нет).
    macro broadcasts(inserts_by = :append, target = nil, partial = nil)
      {% stream_lit = @type.name.stringify.underscore %}
      {% target_expr = target.is_a?(SymbolLiteral) ? target.stringify : target %}
      after_commit(on: :create) do
        broadcast_action_later_to([{{ stream_lit }}.pluralize],
          action: {{ inserts_by }}, target: {{ target_expr || "broadcast_target_default".id }},
          partial: {{ partial }})
      end
      after_commit(on: :update) do
        broadcast_replace_later_to([{{ stream_lit }}.pluralize], partial: {{ partial }})
      end
      after_commit(on: :destroy) do
        broadcast_remove_to([{{ stream_lit }}.pluralize])
      end
    end

    macro broadcasts_refreshes_to(stream)
      {% stream_expr = stream.is_a?(SymbolLiteral) ? stream.id : stream %}
      after_commit do
        broadcast_refresh_later_to([{{ stream_expr }}])
      end
    end

    macro broadcasts_refreshes
      {% stream_lit = @type.name.stringify.underscore.pluralize %}
      after_commit do
        broadcast_refresh_later_to([{{ stream_lit }}])
      end
    end

    # --- instance API ----------------------------------------------------
    # streamables: nil — стрим сама запись (по GlobalID), как broadcast_*
    # без _to в Rails. Все методы делегируют в Turbo::StreamsChannel,
    # предварительно заполнив дефолты рендера (см. __turbo_fill).

    def broadcast_remove_to(streamables : Array(Turbo::Streamable), *,
                            target : Turbo::DomTarget = self) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_remove_to(streamables, target: target)
    end

    def broadcast_remove(*, target : Turbo::DomTarget = self) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_remove_to([self], target: target)
    end

    def broadcast_replace_to(streamables : Array(Turbo::Streamable), *,
                             target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                             content : String? = nil, html : String? = nil,
                             partial : String? = nil, template : String? = nil,
                             locals : Hash(String, Turbo::RenderVal)? = nil,
                             assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, html, nil, target, targets, self)
      Turbo::StreamsChannel.broadcast_replace_to(streamables, target: o[:target], targets: targets,
                                                 content: content, html: html,
                                                 partial: o[:partial], template: template,
                                                 locals: o[:locals], assigns: assigns)
    end

    def broadcast_replace(*, content : String? = nil, html : String? = nil,
                          partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, self, nil, self)
      Turbo::StreamsChannel.broadcast_replace_to([self], target: self,
                                                 content: content, html: html,
                                                 partial: o[:partial], locals: o[:locals])
    end

    def broadcast_update_to(streamables : Array(Turbo::Streamable), *,
                            target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                            content : String? = nil, html : String? = nil,
                            partial : String? = nil, template : String? = nil,
                            locals : Hash(String, Turbo::RenderVal)? = nil,
                            assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, html, nil, target, targets, self)
      Turbo::StreamsChannel.broadcast_update_to(streamables, target: o[:target], targets: targets,
                                                content: content, html: html,
                                                partial: o[:partial], template: template,
                                                locals: o[:locals], assigns: assigns)
    end

    def broadcast_update(*, content : String? = nil, html : String? = nil,
                         partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, self, nil, self)
      Turbo::StreamsChannel.broadcast_update_to([self], target: self,
                                                content: content, html: html,
                                                partial: o[:partial], locals: o[:locals])
    end

    def broadcast_before_to(streamables : Array(Turbo::Streamable), *,
                            target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                            content : String? = nil, html : String? = nil,
                            partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, target, targets, nil)
      Turbo::StreamsChannel.broadcast_before_to(streamables, target: target, targets: targets,
                                                content: content, html: html,
                                                partial: o[:partial], locals: o[:locals])
    end

    def broadcast_after_to(streamables : Array(Turbo::Streamable), *,
                           target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                           content : String? = nil, html : String? = nil,
                           partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, target, targets, nil)
      Turbo::StreamsChannel.broadcast_after_to(streamables, target: target, targets: targets,
                                               content: content, html: html,
                                               partial: o[:partial], locals: o[:locals])
    end

    def broadcast_append_to(streamables : Array(Turbo::Streamable), *,
                            target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                            content : String? = nil, html : String? = nil,
                            partial : String? = nil, template : String? = nil,
                            locals : Hash(String, Turbo::RenderVal)? = nil,
                            assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, html, nil, target, targets,
                       __turbo_default_target)
      Turbo::StreamsChannel.broadcast_append_to(streamables, target: o[:target], targets: targets,
                                                content: content, html: html,
                                                partial: o[:partial], template: template,
                                                locals: o[:locals], assigns: assigns)
    end

    def broadcast_append(*, target : Turbo::DomTarget = nil,
                         content : String? = nil, html : String? = nil,
                         partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, target, nil, __turbo_default_target)
      Turbo::StreamsChannel.broadcast_append_to([self], target: o[:target],
                                                content: content, html: html,
                                                partial: o[:partial], locals: o[:locals])
    end

    def broadcast_prepend_to(streamables : Array(Turbo::Streamable), *,
                             target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                             content : String? = nil, html : String? = nil,
                             partial : String? = nil, template : String? = nil,
                             locals : Hash(String, Turbo::RenderVal)? = nil,
                             assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, html, nil, target, targets,
                       __turbo_default_target)
      Turbo::StreamsChannel.broadcast_prepend_to(streamables, target: o[:target], targets: targets,
                                                 content: content, html: html,
                                                 partial: o[:partial], template: template,
                                                 locals: o[:locals], assigns: assigns)
    end

    def broadcast_prepend(*, target : Turbo::DomTarget = nil,
                          content : String? = nil, html : String? = nil,
                          partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, target, nil, __turbo_default_target)
      Turbo::StreamsChannel.broadcast_prepend_to([self], target: o[:target],
                                                 content: content, html: html,
                                                 partial: o[:partial], locals: o[:locals])
    end

    def broadcast_refresh_to(streamables : Array(Turbo::Streamable)) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_refresh_to(streamables)
    end

    def broadcast_refresh : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_refresh_to([self])
    end

    def broadcast_refresh_later_to(streamables : Array(Turbo::Streamable)) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_refresh_later_to(streamables)
    end

    def broadcast_refresh_later : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_refresh_later_to([self])
    end

    def broadcast_action_to(streamables : Array(Turbo::Streamable), action : String | Symbol, *,
                            target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                            content : String? = nil, html : String? = nil,
                            partial : String? = nil, template : String? = nil,
                            locals : Hash(String, Turbo::RenderVal)? = nil,
                            assigns : Hash(String, Turbo::RenderVal)? = nil,
                            attributes : Hash(String, String) = {} of String => String) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, html, nil, target, targets,
                       __turbo_default_target)
      Turbo::StreamsChannel.broadcast_action_to(streamables, action, target: o[:target],
                                                targets: targets, content: content, html: html,
                                                partial: o[:partial], template: template,
                                                locals: o[:locals], assigns: assigns,
                                                attributes: attributes)
    end

    def broadcast_action(action : String | Symbol, *,
                         target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                         content : String? = nil, html : String? = nil,
                         partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil,
                         attributes : Hash(String, String) = {} of String => String) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, html, nil, target, targets, __turbo_default_target)
      Turbo::StreamsChannel.broadcast_action_to([self], action, target: o[:target],
                                                targets: targets, content: content, html: html,
                                                partial: o[:partial], locals: o[:locals],
                                                attributes: attributes)
    end

    def broadcast_action_later_to(streamables : Array(Turbo::Streamable), action : String | Symbol, *,
                                  target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                                  partial : String? = nil, template : String? = nil,
                                  locals : Hash(String, Turbo::RenderVal)? = nil,
                                  assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, nil, nil, target, targets,
                       __turbo_default_target)
      Turbo::StreamsChannel.broadcast_action_later_to(streamables, action, target: o[:target],
                                                      targets: targets, partial: o[:partial],
                                                      template: template, locals: o[:locals],
                                                      assigns: assigns)
    end

    def broadcast_action_later(action : String | Symbol, *,
                               target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                               partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, nil, nil, target, targets, __turbo_default_target)
      Turbo::StreamsChannel.broadcast_action_later_to([self], action, target: o[:target],
                                                      targets: targets, partial: o[:partial],
                                                      locals: o[:locals])
    end

    def broadcast_replace_later_to(streamables : Array(Turbo::Streamable), *,
                                   target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                                   partial : String? = nil, template : String? = nil,
                                   locals : Hash(String, Turbo::RenderVal)? = nil,
                                   assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, nil, nil, target, targets, self)
      Turbo::StreamsChannel.broadcast_replace_later_to(streamables, target: o[:target],
                                                       targets: targets, partial: o[:partial],
                                                       template: template, locals: o[:locals],
                                                       assigns: assigns)
    end

    def broadcast_replace_later(*, partial : String? = nil,
                                locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, nil, nil, self, nil, self)
      Turbo::StreamsChannel.broadcast_replace_later_to([self], target: self,
                                                       partial: o[:partial], locals: o[:locals])
    end

    def broadcast_update_later_to(streamables : Array(Turbo::Streamable), *,
                                  target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                                  partial : String? = nil, template : String? = nil,
                                  locals : Hash(String, Turbo::RenderVal)? = nil,
                                  assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, nil, nil, target, targets, self)
      Turbo::StreamsChannel.broadcast_update_later_to(streamables, target: o[:target],
                                                      targets: targets, partial: o[:partial],
                                                      template: template, locals: o[:locals],
                                                      assigns: assigns)
    end

    def broadcast_update_later(*, partial : String? = nil,
                               locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, nil, nil, self, nil, self)
      Turbo::StreamsChannel.broadcast_update_later_to([self], target: self,
                                                      partial: o[:partial], locals: o[:locals])
    end

    def broadcast_append_later_to(streamables : Array(Turbo::Streamable), *,
                                  target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                                  partial : String? = nil, template : String? = nil,
                                  locals : Hash(String, Turbo::RenderVal)? = nil,
                                  assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, nil, nil, target, targets,
                       __turbo_default_target)
      Turbo::StreamsChannel.broadcast_append_later_to(streamables, target: o[:target],
                                                      targets: targets, partial: o[:partial],
                                                      template: template, locals: o[:locals],
                                                      assigns: assigns)
    end

    def broadcast_append_later(*, target : Turbo::DomTarget = nil,
                               partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, nil, nil, target, nil, __turbo_default_target)
      Turbo::StreamsChannel.broadcast_append_later_to([self], target: o[:target],
                                                      partial: o[:partial], locals: o[:locals])
    end

    def broadcast_prepend_later_to(streamables : Array(Turbo::Streamable), *,
                                   target : Turbo::DomTarget = nil, targets : Turbo::DomTarget = nil,
                                   partial : String? = nil, template : String? = nil,
                                   locals : Hash(String, Turbo::RenderVal)? = nil,
                                   assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, template, locals, nil, nil, target, targets,
                       __turbo_default_target)
      Turbo::StreamsChannel.broadcast_prepend_later_to(streamables, target: o[:target],
                                                       targets: targets, partial: o[:partial],
                                                       template: template, locals: o[:locals],
                                                       assigns: assigns)
    end

    def broadcast_prepend_later(*, target : Turbo::DomTarget = nil,
                                partial : String? = nil, locals : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      o = __turbo_fill(partial, nil, locals, nil, nil, target, nil, __turbo_default_target)
      Turbo::StreamsChannel.broadcast_prepend_later_to([self], target: o[:target],
                                                       partial: o[:partial], locals: o[:locals])
    end

    def broadcast_render_to(streamables : Array(Turbo::Streamable), *,
                            template : String? = nil,
                            assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_render_to(streamables, template: template, assigns: assigns)
    end

    def broadcast_render(*, template : String? = nil,
                         assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_render_to([self], template: template, assigns: assigns)
    end

    def broadcast_render_later_to(streamables : Array(Turbo::Streamable), *,
                                  template : String? = nil,
                                  assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_render_later_to(streamables, template: template, assigns: assigns)
    end

    def broadcast_render_later(*, template : String? = nil,
                               assigns : Hash(String, Turbo::RenderVal)? = nil) : Nil
      return if __turbo_suppressed?
      Turbo::StreamsChannel.broadcast_render_later_to([self], template: template, assigns: assigns)
    end

    # extract_options_and_add_target + broadcast_rendering_with_defaults.
    private def __turbo_fill(partial : String?, template : String?,
                             locals : Hash(String, Turbo::RenderVal)?, html : String?,
                             render : Bool?, target : Turbo::DomTarget,
                             targets : Turbo::DomTarget, default_target : Turbo::DomTarget)
      merged = {} of String => Turbo::RenderVal
      merged[self.class.name.underscore] = self
      locals.try { |ls| ls.each { |k, v| merged[k] = v } }

      resolved_partial = partial
      if html.nil? && resolved_partial.nil?
        if template.nil? && render != false
          resolved_partial = to_partial_path
        end
      end

      resolved_target = target
      if resolved_target.nil? && targets.nil?
        resolved_target = default_target
      end

      {partial: resolved_partial, locals: merged, target: resolved_target}
    end

    private def __turbo_default_target : String
      self.class.broadcast_target_default
    end

    private def __turbo_suppressed? : Bool
      self.class.suppressed_turbo_broadcasts?
    end
  end
end
