# View-хелперы turbo: turbo_stream / turbo_stream_from (StreamsHelper)
# и turbo_frame_tag (FramesHelper). 1:1 с app/helpers гема; порядок
# атрибутов зафиксирован оракулом (data → channel → signed-stream-name).

module Turbo
  module StreamsHelper
    # TagBuilder для шаблонов и контроллеров.
    def turbo_stream : Turbo::Streams::TagBuilder
      Turbo::Streams::TagBuilder.new(self)
    end

    # <turbo-cable-stream-source> — подписка на стрим через
    # Turbo::StreamsChannel. channel: — имя кастомного канала,
    # data: — доп. data-атрибуты канала.
    def turbo_stream_from(*streamables : Turbo::Streamable, channel : String? = nil,
                          data : Hash(String, String)? = nil) : ActionView::SafeString
      unless streamables.any? { |s| !s.is_a?(String) || !s.blank? }
        raise ArgumentError.new("streamables can't be blank")
      end
      opts = {} of String => ActionView::Helpers::TagHelper::AttrVal
      if data
        # Rails dasherizes data-ключи: {room_name:} -> data-room-name
        dashed = {} of String => String
        data.each { |k, v| dashed[k.gsub('_', '-')] = v }
        opts["data"] = dashed
      end
      opts["channel"] = channel || "Turbo::StreamsChannel"
      opts["signed-stream-name"] = Turbo::StreamsChannel.signed_stream_name(streamables.to_a)
      ActionView::SafeString.new("<turbo-cable-stream-source#{tag_options(opts)}></turbo-cable-stream-source>")
    end
  end

  module FramesHelper
    # <turbo-frame id="..." [src=...] [loading=...]>; блочная форма —
    # содержимое блока экранируется (content_tag-семантика Rails),
    # SafeString проходит как есть.
    def turbo_frame_tag(frame_id : String | Symbol, src : String? = nil,
                        loading : String? = nil, &block : Proc(String)) : ActionView::SafeString
      opts = {} of String => ActionView::Helpers::TagHelper::AttrVal
      opts["loading"] = loading if loading
      opts["id"] = frame_id.to_s
      opts["src"] = src if src
      result = block.call
      inner = result.is_a?(ActionView::SafeString) ? result.to_s : HTML.escape(result)
      ActionView::SafeString.new("<turbo-frame#{tag_options(opts)}>#{inner}</turbo-frame>")
    end

    def turbo_frame_tag(frame_id : String | Symbol, src : String? = nil,
                        loading : String? = nil) : ActionView::SafeString
      opts = {} of String => ActionView::Helpers::TagHelper::AttrVal
      opts["loading"] = loading if loading
      opts["id"] = frame_id.to_s
      opts["src"] = src if src
      ActionView::SafeString.new("<turbo-frame#{tag_options(opts)}></turbo-frame>")
    end
  end
end
