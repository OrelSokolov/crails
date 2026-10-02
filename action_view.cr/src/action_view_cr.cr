require "html"
# action_view.cr — порт ActionView (хелперы, шаблоны, FormBuilder).
#
# ERB-синтаксис компилируется в методы-рендеры на этапе сборки с
# семантикой Rails: `<%= %>` экранирует (кроме SafeString), блочные
# хелперы работают через общий буфер вывода.

require "active_support_cr"
require "./output_safety"
require "./rendering"
require "./helpers/tag_helper"
require "./helpers/text_helper"
require "./helpers/url_helper"
require "./helpers/asset_tag_helper"
require "./helpers/form_tag_helper"
require "./helpers/form_helper"

module ActionView
  VERSION = "0.1.0"

  module Helpers
    include ActionView::Rendering

    # ECR does not escape `<%= %>` output in hand-written legacy
    # templates; compiled templates auto-escape via __av_esc instead.
    def h(value) : String
      HTML.escape(value.to_s)
    end

    def html_escape(value : String) : String
      HTML.escape(value)
    end

    include TagHelper
    include TextHelper
    include NumberHelper
    include UrlHelper
    include AssetTagHelper
    include FormTagHelper
    include FormHelper
  end
end
