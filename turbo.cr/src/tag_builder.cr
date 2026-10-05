# Turbo::Streams::TagBuilder — 1:1 с app/models/turbo/streams/
# tag_builder.rb. Используется из шаблонов (turbo_stream.append ...),
# из контроллеров и из Broadcasts.
#
# Семантика вывода (зафиксирована оракулом):
#   * позиционный content — БЕЗ экранирования;
#   * блок — содержимое capture ЭКРАНИРУЕТСЯ (Rails capture);
#   * html: kwarg — экранируется (рендер-путь render(html:));
#   * partial: — рендер партиала через Turbo.render_partial;
#   * target-запись без контента — рендер её партиала;
#   * method:/attributes идут перед action/target.
#
# Публичные методы — парами оверлоадов (с блоком/без): Crystal
# требует блок у методов с &block-параметром.

module Turbo
  module Streams
    class TagBuilder
      def initialize(@view : ActionView::Rendering)
      end

      def remove(target : DomTarget) : ActionView::SafeString
        __action("remove", target, nil, nil, nil, nil, nil, false, nil)
      end

      def remove_all(targets : DomTarget) : ActionView::SafeString
        __action_all("remove", targets, nil, nil, nil, nil, nil, false, nil)
      end

      {% for action in %w(append prepend replace update before after) %}
        def {{ action.id }}(target : DomTarget, content : String | ActiveRecord::Base | Nil = nil,
                            *, partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                            html : String? = nil, method : String? = nil) : ActionView::SafeString
          __action({{ action.id.stringify }}, target, content, partial, locals, html, method, true, nil)
        end

        def {{ action.id }}(target : DomTarget, content : String | ActiveRecord::Base | Nil = nil,
                            *, partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                            html : String? = nil, method : String? = nil, &block : Proc(String | Nil)) : ActionView::SafeString
          __action({{ action.id.stringify }}, target, content, partial, locals, html, method, true, block)
        end

        def {{ action.id }}_all(targets : DomTarget, content : String | ActiveRecord::Base | Nil = nil,
                                *, partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                                html : String? = nil, method : String? = nil) : ActionView::SafeString
          __action_all({{ action.id.stringify }}, targets, content, partial, locals, html, method, true, nil)
        end

        def {{ action.id }}_all(targets : DomTarget, content : String | ActiveRecord::Base | Nil = nil,
                                *, partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                                html : String? = nil, method : String? = nil, &block : Proc(String | Nil)) : ActionView::SafeString
          __action_all({{ action.id.stringify }}, targets, content, partial, locals, html, method, true, block)
        end
      {% end %}

      def refresh(attributes : Hash(String, String) = {} of String => String) : ActionView::SafeString
        Turbo::Streams::ActionHelper.refresh_tag(attributes)
      end

      # Кастомное действие: turbo_stream.action(:highlight, "el", ...).
      def action(name : String | Symbol, target : DomTarget,
                 content : String | ActiveRecord::Base | Nil = nil, *,
                 partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                 html : String? = nil, method : String? = nil,
                 allow_inferred_rendering : Bool = true) : ActionView::SafeString
        __action(name.to_s, target, content, partial, locals, html, method,
                 allow_inferred_rendering, nil)
      end

      def action(name : String | Symbol, target : DomTarget,
                 content : String | ActiveRecord::Base | Nil = nil, *,
                 partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                 html : String? = nil, method : String? = nil,
                 allow_inferred_rendering : Bool = true, &block : Proc(String | Nil)) : ActionView::SafeString
        __action(name.to_s, target, content, partial, locals, html, method,
                 allow_inferred_rendering, block)
      end

      def action_all(name : String | Symbol, targets : DomTarget,
                     content : String | ActiveRecord::Base | Nil = nil, *,
                     partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                     html : String? = nil, method : String? = nil,
                     allow_inferred_rendering : Bool = true) : ActionView::SafeString
        __action_all(name.to_s, targets, content, partial, locals, html, method,
                     allow_inferred_rendering, nil)
      end

      def action_all(name : String | Symbol, targets : DomTarget,
                     content : String | ActiveRecord::Base | Nil = nil, *,
                     partial : String? = nil, locals : Hash(String, RenderVal)? = nil,
                     html : String? = nil, method : String? = nil,
                     allow_inferred_rendering : Bool = true, &block : Proc(String | Nil)) : ActionView::SafeString
        __action_all(name.to_s, targets, content, partial, locals, html, method,
                     allow_inferred_rendering, block)
      end

      private def __action(name : String, target : DomTarget,
                           content : String | ActiveRecord::Base | Nil,
                           partial : String?, locals : Hash(String, RenderVal)?,
                           html : String?, method : String?,
                           allow_inferred_rendering : Bool,
                           block : Proc(String | Nil)?) : ActionView::SafeString
        template = __render_template(target, content, partial, locals, html,
                                     allow_inferred_rendering, block)
        attributes = {} of String => String
        attributes["method"] = method if method
        Turbo::Streams::ActionHelper.action_tag(name, target: target, template: template,
                                                attributes: attributes)
      end

      private def __action_all(name : String, targets : DomTarget,
                               content : String | ActiveRecord::Base | Nil,
                               partial : String?, locals : Hash(String, RenderVal)?,
                               html : String?, method : String?,
                               allow_inferred_rendering : Bool,
                               block : Proc(String | Nil)?) : ActionView::SafeString
        template = __render_template(targets, content, partial, locals, html,
                                     allow_inferred_rendering, block)
        attributes = {} of String => String
        attributes["method"] = method if method
        Turbo::Streams::ActionHelper.action_tag(name, targets: targets, template: template,
                                                attributes: attributes)
      end

      private def __render_template(target : DomTarget, content : String | ActiveRecord::Base | Nil,
                                    partial : String?, locals : Hash(String, RenderVal)?,
                                    html : String?, allow_inferred_rendering : Bool,
                                    block : Proc(String | Nil)?) : String?
        case
        when content
          if content.is_a?(ActiveRecord::Base) && allow_inferred_rendering
            Turbo.render_record(content) || content.to_s
          else
            content.to_s
          end
        when block
          HTML.escape(@view.capture { block.call.not_nil! })
        when partial
          l = {} of String => RenderVal
          (locals || {} of String => RenderVal).each { |k, v| l[k.to_s] = v.as(RenderVal) }
          Turbo.render_partial(partial, l)
        when html
          HTML.escape(html)
        else
          if allow_inferred_rendering && target.is_a?(ActiveRecord::Base)
            Turbo.render_record(target)
          end
        end
      end
    end
  end
end
