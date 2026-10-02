# FormHelper / FormBuilder — byte-exact with actionview 8.1.4 (oracle:
# fw_* cases). Models expose form metadata through the FormModel
# interface; ActiveRecord::Base implements it via its attributes hash.

module ActionView
  alias FormValue = String | Int32 | Int64 | Float64 | Bool | Nil

  module FormModel
    abstract def form_scope : String
    abstract def form_attributes : Hash(String, FormValue)
    abstract def form_persisted? : Bool
  end

  module Helpers
    module FormHelper
      include TagHelper
      include FormTagHelper

      # form_with url: "/x" do |f| ... end — same buffer contract as
      # form_tag (open tags, yield, close, return "").
      def form_with(url : String? = nil, model : FormModel? = nil,
                    scope : String? = nil, **opts, &) : String
        scope = model.form_scope if model && !scope
        raise ArgumentError.new("form_with needs a url: or model:") unless url
        opts = __av_opts_to_h(opts)
        method = model.try(&.form_persisted?) ? "patch" : "post"
        __av_out(String.build do |io|
          io << %(<form action="#{HTML.escape(url)}" accept-charset="UTF-8"#{tag_options(opts)} data-remote="true" method="post">)
          io << UTF8_ENROLLMENT
          io << %(<input type="hidden" name="_method" value="#{method}" autocomplete="off" />) unless method == "post"
        end)
        yield FormBuilder.new(self, scope || "", model)
        __av_out "</form>"
        ""
      end

      class FormBuilder
        def initialize(@view : ActionView::Helpers, @scope : String,
                       @model : FormModel? = nil)
        end

        private def value_of(attr : String) : String
          v = @model.try(&.form_attributes[attr]?)
          v.nil? ? "" : v.to_s
        end

        private def name_of(attr : String) : String
          "#{@scope}[#{attr}]"
        end

        def field_name(attr : String | Symbol) : SafeString
          SafeString.new(name_of(attr.to_s))
        end

        def text_field(attr : String | Symbol, **opts) : SafeString
          SafeString.new(%(<input type="text" value="#{HTML.escape(value_of(attr.to_s))}" name="#{name_of(attr.to_s)}"#{@view.tag_options(opts)} />))
        end

        def password_field(attr : String | Symbol, **opts) : SafeString
          SafeString.new(%(<input type="password" value="#{HTML.escape(value_of(attr.to_s))}" name="#{name_of(attr.to_s)}"#{@view.tag_options(opts)} />))
        end

        def hidden_field(attr : String | Symbol, **opts) : SafeString
          SafeString.new(%(<input autocomplete="off" type="hidden" value="#{HTML.escape(value_of(attr.to_s))}" name="#{name_of(attr.to_s)}"#{@view.tag_options(opts)} />))
        end

        def check_box(attr : String | Symbol, **opts) : SafeString
          checked = truthy?(@model.try(&.form_attributes[attr]?)) ? %( checked="checked") : ""
          SafeString.new(
            %(<input name="#{name_of(attr.to_s)}" type="hidden" value="0" autocomplete="off" />) +
            %(<input type="checkbox" value="1"#{checked} name="#{name_of(attr.to_s)}"#{@view.tag_options(opts)} />))
        end

        def radio_button(attr : String | Symbol, tag_value : String, **opts) : SafeString
          checked = value_of(attr) == tag_value ? %( checked="checked") : ""
          SafeString.new(%(<input type="radio" value="#{tag_value}"#{checked} name="#{name_of(attr.to_s)}"#{@view.tag_options(opts)} />))
        end

        def text_area(attr : String | Symbol, **opts) : SafeString
          SafeString.new(%(<textarea name="#{name_of(attr.to_s)}"#{@view.tag_options(opts)}>\n#{HTML.escape(value_of(attr.to_s))}</textarea>))
        end

        def label(attr : String | Symbol, text : String? = nil, **opts) : SafeString
          SafeString.new(%(<label#{@view.tag_options(opts)}>#{HTML.escape(text || attr.to_s.gsub('_', ' ').capitalize)}</label>))
        end

        def submit(value : String = "Save changes", **opts) : SafeString
          SafeString.new(%(<input type="submit" name="commit" value="#{HTML.escape(value)}"#{@view.tag_options(opts)} data-disable-with="#{HTML.escape(value)}" />))
        end

        private def truthy?(value : FormValue) : Bool
          case value
          when Bool then value
          when String then value == "true" || value == "1"
              else !!value
          end
        end
      end
    end
  end
end
