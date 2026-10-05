# Turbo::Streams::Broadcasts + Turbo::StreamsChannel — 1:1 с
# app/channels/turbo/streams/broadcasts.rb и streams_channel.rb
# (turbo-rails 2.0.20; broadcast_refresh_to в 2.0.20 не принимает
# атрибутов — оракул это фиксирует).

module Turbo
  module Streams
    module Broadcasts
      # Подписанное имя стрима (для turbo_stream_from).
      def signed_stream_name(streamables : Array(Streamable)) : String
        Turbo::Streams::StreamName.signed_stream_name(streamables)
      end

      def verified_stream_name(signed : String) : String?
        Turbo::Streams::StreamName.verified_stream_name(signed)
      end

      def broadcast_remove_to(streamables : Array(Streamable), *,
                              target : DomTarget = nil, targets : DomTarget = nil) : Nil
        broadcast_action_to(streamables, :remove, target: target, targets: targets, render: false)
      end

      def broadcast_replace_to(streamables : Array(Streamable), *,
                               target : DomTarget = nil, targets : DomTarget = nil,
                               content : String? = nil, html : String? = nil,
                               partial : String? = nil, template : String? = nil,
                               locals : Hash(String, RenderVal)? = nil,
                               assigns : Hash(String, RenderVal)? = nil,
                               render : Bool? = nil) : Nil
        broadcast_action_to(streamables, :replace, target: target, targets: targets,
                            content: content, html: html, partial: partial, template: template,
                            locals: locals, assigns: assigns, render: render)
      end

      def broadcast_update_to(streamables : Array(Streamable), *,
                              target : DomTarget = nil, targets : DomTarget = nil,
                              content : String? = nil, html : String? = nil,
                              partial : String? = nil, template : String? = nil,
                              locals : Hash(String, RenderVal)? = nil,
                              assigns : Hash(String, RenderVal)? = nil,
                              render : Bool? = nil) : Nil
        broadcast_action_to(streamables, :update, target: target, targets: targets,
                            content: content, html: html, partial: partial, template: template,
                            locals: locals, assigns: assigns, render: render)
      end

      def broadcast_before_to(streamables : Array(Streamable), *,
                              target : DomTarget = nil, targets : DomTarget = nil,
                              content : String? = nil, html : String? = nil,
                              partial : String? = nil, template : String? = nil,
                              locals : Hash(String, RenderVal)? = nil,
                              assigns : Hash(String, RenderVal)? = nil,
                              render : Bool? = nil) : Nil
        broadcast_action_to(streamables, :before, target: target, targets: targets,
                            content: content, html: html, partial: partial, template: template,
                            locals: locals, assigns: assigns, render: render)
      end

      def broadcast_after_to(streamables : Array(Streamable), *,
                             target : DomTarget = nil, targets : DomTarget = nil,
                             content : String? = nil, html : String? = nil,
                             partial : String? = nil, template : String? = nil,
                             locals : Hash(String, RenderVal)? = nil,
                             assigns : Hash(String, RenderVal)? = nil,
                             render : Bool? = nil) : Nil
        broadcast_action_to(streamables, :after, target: target, targets: targets,
                            content: content, html: html, partial: partial, template: template,
                            locals: locals, assigns: assigns, render: render)
      end

      def broadcast_append_to(streamables : Array(Streamable), *,
                              target : DomTarget = nil, targets : DomTarget = nil,
                              content : String? = nil, html : String? = nil,
                              partial : String? = nil, template : String? = nil,
                              locals : Hash(String, RenderVal)? = nil,
                              assigns : Hash(String, RenderVal)? = nil,
                              render : Bool? = nil) : Nil
        broadcast_action_to(streamables, :append, target: target, targets: targets,
                            content: content, html: html, partial: partial, template: template,
                            locals: locals, assigns: assigns, render: render)
      end

      def broadcast_prepend_to(streamables : Array(Streamable), *,
                               target : DomTarget = nil, targets : DomTarget = nil,
                               content : String? = nil, html : String? = nil,
                               partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                               render : Bool? = nil) : Nil
        broadcast_action_to(streamables, :prepend, target: target, targets: targets,
                            content: content, html: html, partial: partial, locals: locals, render: render)
      end

      def broadcast_refresh_to(streamables : Array(Streamable)) : Nil
        broadcast_stream_to(streamables, content: Turbo::Streams::ActionHelper.refresh_tag)
      end

      def broadcast_action_to(streamables : Array(Streamable), action : String | Symbol, *,
                              target : DomTarget = nil, targets : DomTarget = nil,
                              content : String? = nil, html : String? = nil,
                              partial : String? = nil, template : String? = nil,
                              locals : Hash(String, RenderVal)? = nil,
                              assigns : Hash(String, RenderVal)? = nil,
                              render : Bool? = nil,
                              attributes : Hash(String, String) = {} of String => String) : Nil
        template_html = __render_broadcast_action(content, html, partial, template, locals, assigns, render)
        broadcast_stream_to(streamables, content: Turbo::Streams::ActionHelper.action_tag(
          action, target: target, targets: targets, template: template_html, attributes: attributes))
      end

      # --- later-варианты (через ActiveJob) -----------------------------

      def broadcast_replace_later_to(streamables : Array(Streamable), *,
                                     target : DomTarget = nil, targets : DomTarget = nil,
                                     partial : String? = nil, template : String? = nil,
                                     locals : Hash(String, RenderVal)? = nil,
                                     assigns : Hash(String, RenderVal)? = nil) : Nil
        broadcast_action_later_to(streamables, :replace, target: target, targets: targets,
                                  partial: partial, template: template, locals: locals, assigns: assigns)
      end

      def broadcast_update_later_to(streamables : Array(Streamable), *,
                                    target : DomTarget = nil, targets : DomTarget = nil,
                                    partial : String? = nil, template : String? = nil,
                                    locals : Hash(String, RenderVal)? = nil,
                                    assigns : Hash(String, RenderVal)? = nil) : Nil
        broadcast_action_later_to(streamables, :update, target: target, targets: targets,
                                  partial: partial, template: template, locals: locals, assigns: assigns)
      end

      def broadcast_before_later_to(streamables : Array(Streamable), *,
                                    target : DomTarget = nil, targets : DomTarget = nil,
                                    partial : String? = nil, template : String? = nil,
                                    locals : Hash(String, RenderVal)? = nil,
                                    assigns : Hash(String, RenderVal)? = nil) : Nil
        broadcast_action_later_to(streamables, :before, target: target, targets: targets,
                                  partial: partial, template: template, locals: locals, assigns: assigns)
      end

      def broadcast_after_later_to(streamables : Array(Streamable), *,
                                   target : DomTarget = nil, targets : DomTarget = nil,
                                   partial : String? = nil, template : String? = nil,
                                   locals : Hash(String, RenderVal)? = nil,
                                   assigns : Hash(String, RenderVal)? = nil) : Nil
        broadcast_action_later_to(streamables, :after, target: target, targets: targets,
                                  partial: partial, template: template, locals: locals, assigns: assigns)
      end

      def broadcast_append_later_to(streamables : Array(Streamable), *,
                                    target : DomTarget = nil, targets : DomTarget = nil,
                                    partial : String? = nil, template : String? = nil,
                                    locals : Hash(String, RenderVal)? = nil,
                                    assigns : Hash(String, RenderVal)? = nil) : Nil
        broadcast_action_later_to(streamables, :append, target: target, targets: targets,
                                  partial: partial, template: template, locals: locals, assigns: assigns)
      end

      def broadcast_prepend_later_to(streamables : Array(Streamable), *,
                                     target : DomTarget = nil, targets : DomTarget = nil,
                                     partial : String? = nil, template : String? = nil,
                                     locals : Hash(String, RenderVal)? = nil,
                                     assigns : Hash(String, RenderVal)? = nil) : Nil
        broadcast_action_later_to(streamables, :prepend, target: target, targets: targets,
                                  partial: partial, template: template, locals: locals, assigns: assigns)
      end

      def broadcast_action_later_to(streamables : Array(Streamable), action : String | Symbol, *,
                                    target : DomTarget = nil, targets : DomTarget = nil,
                                    partial : String? = nil, template : String? = nil,
                                    locals : Hash(String, RenderVal)? = nil,
                                    assigns : Hash(String, RenderVal)? = nil,
                                    attributes : Hash(String, String) = {} of String => String) : Nil
        cleaned = streamables.reject { |s| s.is_a?(String) && s.blank? }
        return if cleaned.empty?
        payload = {} of String | Symbol => ActiveJob::ArgValue
        payload["target"] = Turbo::Streams::ActionHelper.convert_to_dom_id(target)
        payload["targets"] = Turbo::Streams::ActionHelper.convert_to_dom_id(targets, include_selector: true)
        attrs = {} of String | Symbol => ActiveJob::ArgValue
        attributes.each { |k, v| attrs[k] = v }
        payload["attributes"] = attrs
        payload["rendering"] = Turbo::JobRendering.encode(partial, template, Turbo.cast_locals(locals), Turbo.cast_locals(assigns))
        Turbo::Streams::ActionBroadcastJob.perform_later(
          Turbo::Streams::StreamName.stream_name_from(cleaned),
          action.to_s,
          payload)
      end

      # Рендер turbo_stream-шаблона с несколькими действиями.
      def broadcast_render_to(streamables : Array(Streamable), *,
                              template : String? = nil,
                              assigns : Hash(String, RenderVal)? = nil) : Nil
        return unless template
        broadcast_stream_to(streamables, content: Turbo.render_template(template, Turbo.cast_locals(assigns || {} of String => RenderVal)))
      end

      def broadcast_render_later_to(streamables : Array(Streamable), *,
                                    template : String? = nil,
                                    assigns : Hash(String, RenderVal)? = nil) : Nil
        return unless template
        cleaned = streamables.reject { |s| s.is_a?(String) && s.blank? }
        return if cleaned.empty?
        Turbo::Streams::BroadcastJob.perform_later(
          Turbo::Streams::StreamName.stream_name_from(cleaned),
          Turbo::JobRendering.encode(nil, template, nil, Turbo.cast_locals(assigns)))
      end

      # Страница обновится (refresh-later; без debounce — отклонение P0).
      def broadcast_refresh_later_to(streamables : Array(Streamable)) : Nil
        cleaned = streamables.reject { |s| s.is_a?(String) && s.blank? }
        return if cleaned.empty?
        Turbo::Streams::BroadcastStreamJob.perform_later(
          Turbo::Streams::StreamName.stream_name_from(cleaned),
          Turbo::Streams::ActionHelper.refresh_tag)
      end

      def broadcast_stream_to(streamables : Array(Streamable), *,
                              content : String | ActionView::SafeString) : Nil
        cleaned = streamables.reject { |s| s.is_a?(String) && s.blank? }
        return if cleaned.empty?
        Turbo.cable.broadcast(Turbo::Streams::StreamName.stream_name_from(cleaned), content.to_s)
      end

      private def __render_broadcast_action(content : String?, html : String?,
                                            partial : String?, template : String?,
                                            locals : Hash?,
                                            assigns : Hash?,
                                            render : Bool?) : String?
        return nil if render == false
        return content if content
        return html if html
        if partial || template
          if partial
            l = {} of String => RenderVal
            (locals || {} of String => RenderVal).each { |k, v| l[k.to_s] = v.as(RenderVal) }
            Turbo.render_partial(partial, l)
          else
            a = {} of String => RenderVal
            (assigns || {} of String => RenderVal).each { |k, v| a[k.to_s] = v.as(RenderVal) }
            Turbo.render_template(template.not_nil!, a)
          end
        end
      end
    end
  end
end

# Канал: подписка по подписанному имени стрима из params.
class Turbo::StreamsChannel < ActionCable::Channel::Base
  extend Turbo::Streams::Broadcasts

  def subscribed : Nil
    if (signed = params["signed_stream_name"]?) &&
       (stream_name = Turbo::StreamsChannel.verified_stream_name(signed))
      stream_from(stream_name)
    else
      reject
    end
  end
end
