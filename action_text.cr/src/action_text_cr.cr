# action_text_cr — port of ActionText (P0): Content/Fragment over
# lexbor, plain-text conversion, safe-list sanitizer with the trix
# layout, RichText storage and the has_rich_text DSL for AR models.

require "lexbor"
require "active_record_cr"

require "./fragment"
require "./plain_text_conversion"
require "./sanitizer"
require "./content"
require "./rich_text"
