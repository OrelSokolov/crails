# Plain-text conversion — 1:1 port of ActionText::PlainTextConversion
# (actiontext 8.1.4): a bottom-up fold over the HTML tree with per-tag
# rules. `remove_trailing_newlines` mirrors Ruby's `chomp("")` (removes
# ALL trailing newlines).

module ActionText
  module PlainTextConversion
    def self.node_to_plain_text(node : Lexbor::Node) : String
      remove_trailing_newlines(reduce(node))
    end

    def self.reduce(node : Lexbor::Node) : String
      if node.tag_id == Lexbor::Lib::TagIdT::LXB_TAG__TEXT
        return remove_trailing_newlines(node.tag_text)
      end
      if node.tag_id == Lexbor::Lib::TagIdT::LXB_TAG__EM_COMMENT
        return ""
      end

      case node.tag_name.downcase
      when "script", "style"
        ""
      when "h1", "h2", "h3", "h4", "h5", "h6", "p"
        block(children_text(node))
      when "ul", "ol"
        text = block(children_text(node))
        list_depth(node) > 0 ? "\n#{text}" : text
      when "br"
        "\n"
      when "div"
        "#{remove_trailing_newlines(children_text(node))}\n"
      when "figcaption"
        "[#{remove_trailing_newlines(children_text(node))}]"
      when "blockquote"
        text = block(children_text(node))
        if text.strip.empty?
          "“”"
        else
          quote_text(text)
        end
      when "li"
        bullet = bullet_for(node)
        indent = list_depth(node) > 1 ? "  " * (list_depth(node) - 1) : ""
        "#{indent}#{bullet} #{remove_trailing_newlines(children_text(node))}\n"
      else
        children_text(node)
      end
    end

    def self.children_text(node : Lexbor::Node) : String
      String.build do |io|
        node.children.each { |child| io << reduce(child) }
      end
    end

    def self.block(text : String) : String
      "#{remove_trailing_newlines(text)}\n\n"
    end

    # Ruby: insert(rindex(/\S/)+1, "”") then insert(index(/\S/), "“")
    def self.quote_text(text : String) : String
      first = last = nil
      text.each_char_with_index do |c, i|
        unless c.whitespace?
          first ||= i
          last = i
        end
      end
      raise("blank blockquote") unless first && last
      if first == last
        text.insert(first, "“").insert(last + 2, "”")
      else
        text.insert(last.not_nil! + 1, "”").insert(first.not_nil!, "“")
      end
    end

    def self.bullet_for(node : Lexbor::Node) : String
      if (parent = node.parent) && (name = parent.tag_name.downcase) && (name == "ol")
        # Ruby: node.parent.elements.index(node) — position among ELEMENT children
        seen = 0
        parent.children.each do |c|
          break if c.element == node.element
          seen += 1 if c.tag_id != Lexbor::Lib::TagIdT::LXB_TAG__TEXT
        end
        "#{seen + 1}."
      else
        "•"
      end
    end

    # Number of ul/ol ancestors (Ruby: ancestors.grep(/^[uo]l$/).count).
    def self.list_depth(node : Lexbor::Node) : Int32
      depth = 0
      current = node.parent
      while current
        name = current.tag_name.downcase
        depth += 1 if name == "ul" || name == "ol"
        current = current.parent
      end
      depth
    end

    def self.remove_trailing_newlines(text : String) : String
      i = text.bytesize
      while i > 0 && text.to_unsafe[i - 1] == '\n'.ord.to_u8
        i -= 1
      end
      text.byte_slice(0, i)
    end
  end
end
