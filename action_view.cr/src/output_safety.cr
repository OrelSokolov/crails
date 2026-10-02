# Output safety (SafeBuffer analog).
#
# Crystal's String cannot be subclassed, so a safe string is a thin
# wrapper type instead. `<%= %>` in compiled templates appends String
# escaped and SafeString raw — same contract as Rails ERB.

module ActionView
  class SafeString
    getter raw : String

    def initialize(@raw : String)
    end

    def html_safe? : Bool
      true
    end

    def to_s : String
      @raw
    end

    def to_s(io : IO) : Nil
      io << @raw
    end

    def +(other : SafeString | String) : SafeString
      SafeString.new(@raw + other.to_s)
    end
  end

  module Helpers
    # Marks a string as trusted HTML: `<%= raw x %>` appends it as-is.
    def raw(value : String) : SafeString
      SafeString.new(value)
    end

    def raw(value : SafeString) : SafeString
      value
    end

    def html_escape(value : String) : String
      HTML.escape(value)
    end

    # `&` untouched when it already starts an entity (`&amp;` etc.).
    def escape_once(value : String) : String
      value.gsub(/&(?!([a-zA-Z]+|#\d+);)/, "&amp;")
        .gsub('<', "&lt;")
        .gsub('>', "&gt;")
        .gsub('"', "&quot;")
        .gsub('\'', "&#39;")
    end

    # Escapes unsafe elements, passes SafeString through untouched.
    def safe_join(elements : Array(String | SafeString), separator : String = "") : SafeString
      SafeString.new(elements.map { |e|
        e.is_a?(SafeString) ? e.raw : HTML.escape(e.to_s)
      }.join(separator))
    end
  end
end

class String
  def html_safe : ActionView::SafeString
    ActionView::SafeString.new(self)
  end

  def html_safe? : Bool
    false
  end
end
