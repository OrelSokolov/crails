# TagHelper: tag()/content_tag()/tag.<name> — byte-exact with
# actionview 8.1.4 (oracle: tag_*, ct_* cases).
#
# Quirk preserved from Rails: `tag("br")` emits `<br />`, while the
# dot form `tag.br` emits `<br>` (TagBuilder#tag_string).

module ActionView
  module Helpers
    module TagHelper
      # Escapes attribute values the way Rails tag_options does.
      def self.__av_attr_escape(value : String) : String
        value.gsub('&', "&amp;")
          .gsub('"', "&quot;")
          .gsub('<', "&lt;")
          .gsub('>', "&gt;")
      end

      def __av_attr_escape(value : String) : String
        TagHelper.__av_attr_escape(value)
      end

      def self.__av_value_to_s(value) : String
        value.to_s
      end

      def __av_value_to_s(value) : String
        value.to_s
      end

      # Renders `key="value"` pairs: booleans as `key="key"` / omitted,
      # nil omitted, nested `data:`/`aria:` hashes flattened. Accepts
      # both Hash and NamedTuple (what `**opts` double splats to).
      # Normalizes `**opts` double splats (NamedTuple, possibly empty)
      # into String-keyed hashes.
      alias AttrVal = String | Int32 | Int64 | Float64 | Bool | Nil | Hash(String, String)

      def __av_opts_to_h(opts) : Hash(String, AttrVal)
        h = {} of String => AttrVal
        opts.each do |k, v|
          h[k.to_s] = v.is_a?(Symbol) ? v.to_s : v.as(AttrVal)
        end
        h
      end

      def tag_options(opts) : String
        String.build do |io|
          opts.each do |key, value|
            __av_tag_option(io, key.to_s, value)
          end
        end
      end

      # Static entry point for code outside a view (turbo.cr's tag
      # builders run on channel/model classes, not view instances).
      def self.tag_options(opts) : String
        String.build do |io|
          opts.each do |key, value|
            new_tag_option(io, key.to_s, value)
          end
        end
      end

      private def __av_tag_option(io : IO, key : String, value) : Nil
        TagHelper.new_tag_option(io, key, value)
      end

      def self.new_tag_option(io : IO, key : String, value) : Nil
        case value
        when Bool
          io << " " << key << %(="#{key}") if value
        when Nil
          # omitted
        when Hash
          value.each do |nested_key, nested_value|
            new_tag_option(io, "#{key}-#{nested_key}", nested_value)
          end
        else
          io << " " << key << "=" << '"' << __av_attr_escape(__av_value_to_s(value)) << '"'
        end
      end

      # `tag("br")` -> `<br />`; `tag("img", src: ...)` -> `<img src="..." />`
      def tag(name : String | Symbol, **attrs) : SafeString
        SafeString.new("<#{name}#{tag_options(attrs)} />")
      end

      # Dot form: `tag.br` -> `<br>` (no closing slash, as in Rails).
      def tag : TagBuilder
        TagBuilder.new(self)
      end

      def content_tag(name : String | Symbol, content : String? = nil, **attrs) : SafeString
        inner = content ? HTML.escape(content) : ""
        SafeString.new("<#{name}#{tag_options(attrs)}>#{inner}</#{name}>")
      end

      def content_tag(name : String | Symbol, **attrs, &) : SafeString
        body = capture { yield }
        SafeString.new("<#{name}#{tag_options(attrs)}>#{body}</#{name}>")
      end

      # `tag.div class: "x" { ... }` / `tag.br`
      class TagBuilder
        def initialize(@view : ActionView::Helpers)
        end

        macro method_missing(call)
          {% extra = "" %}
          {% unless call.named_args.is_a?(Nop) %}
            {% extra = "**{ " + call.named_args.map { |na| "#{na.name.id}: #{na.value}" }.join(", ") + " }" %}
          {% end %}
          {% if call.block %}
            @view.content_tag({{ call.name.stringify }}, {{ extra.id }}) {{ call.block }}
          {% else %}
            __av_tag_string({{ call.name.stringify }}, {{ extra.id }})
          {% end %}
        end

        def __av_tag_string(name : String, **attrs) : String
          "<#{name}#{@view.tag_options(attrs)}>"
        end
      end
    end
  end
end
