# Turbo::Streams::ActionHelper — turbo_stream_action_tag /
# turbo_stream_refresh_tag (1:1 с app/helpers/turbo/streams/
# action_helper.rb). Байт-в-байт с оракулом:
#   * атрибуты доп. опций идут ПЕРЕД action/target (вставка в порядке
#     объявления, как **attributes в Ruby);
#   * remove/refresh — без <template>; остальные — template обёрнут
#     без экранирования (текст в проводе безопасен по построению).

module Turbo
  module Streams
    module ActionHelper
      # target/targets: запись -> dom_id (targets — с "#").
      def self.convert_to_dom_id(target : DomTarget, include_selector : Bool = false) : String?
        case target
        when ActiveRecord::Base
          "#{include_selector ? "#" : ""}#{ActionView::Helpers::RecordIdentifier.dom_id(target)}"
        when String then target
        when Symbol then target.to_s
        else             nil
        end
      end

      def self.action_tag(action : String | Symbol, target : DomTarget = nil,
                          targets : DomTarget = nil, template : String? = nil,
                          attributes : Hash(String, String) = {} of String => String) : ActionView::SafeString
        action_s = action.to_s
        tpl = {"remove", "refresh"}.includes?(action_s) ? "" : "<template>#{template}</template>"

        opts = {} of String => ActionView::Helpers::TagHelper::AttrVal
        attributes.each { |k, v| opts[k] = v }
        opts["action"] = action_s
        if (t = convert_to_dom_id(target))
          opts["target"] = t
        elsif (ts = convert_to_dom_id(targets, include_selector: true))
          opts["targets"] = ts
        end
        ActionView::SafeString.new("<turbo-stream#{ActionView::Helpers::TagHelper.tag_options(opts)}>#{tpl}</turbo-stream>")
      end

      def self.refresh_tag(attributes : Hash(String, String) = {} of String => String) : ActionView::SafeString
        action_tag(:refresh, attributes: attributes)
      end
    end
  end
end
