# Content: wraps an HTML fragment (the gem's ActionText::Content with
# Serialization + the static trix-content layout). `to_s` renders the
# sanitized body inside the layout — byte-identical to the gem's
# layout render (oracle cases rt_to_s_*).

module ActionText
  class Content
    getter fragment : Fragment

    def initialize(content : Content | String | Nil = nil)
      @fragment = case content
                  when Content then content.fragment
                  when String  then Fragment.from_html(content)
                  else              Fragment.from_html("")
                  end
    end

    def self.load(html : String?) : Content?
      Content.new(html) if html
    end

    def self.dump(content : Content | RichText | String | Nil) : String?
      case content
      when Nil       then nil
      when Content   then content.to_html
      when RichText  then content.body.to_s
      else                Content.new(content.as(String)).to_html
      end
    end

    def to_html : String
      fragment.to_html
    end

    def to_plain_text : String
      PlainTextConversion.node_to_plain_text(fragment.root)
    end

    def links : Array(String)
      out = [] of String
      fragment.root.nodes(:a) do |node|
        if (href = node["href"]?) && !out.includes?(href)
          out << href
        end
      end
      out
    end

    # The gem renders this through the action_text/contents/content
    # layout (a static wrapper around the sanitized body).
    def to_s : String
      "<div class=\"trix-content\">\n  #{Sanitizer.sanitize(to_html)}\n</div>\n"
    end

    def to_trix_html : String
      to_s
    end

    def inspect(io : IO) : Nil
      io << "#<ActionText::Content " << to_html.truncate(25).inspect << ">"
    end
  end
end
