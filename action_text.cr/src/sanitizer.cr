# Safe-list sanitizer mirroring ActionText::ContentHelper.sanitize_
# action_text_content: the Rails::HTML4::Sanitizer safe list plus the
# action-text attachment tags/attributes (the oracle captures this exact
# configuration).
#
# Semantics (verified against rails-html-sanitizer 1.7.1 / libxml2):
#   * tags outside the safe list are unwrapped (children kept);
#   * script/style are unwrapped too — their text content survives;
#   * attributes outside the list are dropped;
#   * libxml2 newline artifact: when an unwrapped node was the last
#     element child of an allowed (non-root) element, a "\n" follows its
#     content (oracle cases sz_script / rt_to_s_san).

module ActionText
  module Sanitizer
    TAGS = %w[
      a abbr acronym address b big blockquote br cite code dd del dfn div
      dl dt em h1 h2 h3 h4 h5 h6 hr i img ins kbd li mark ol p pre samp
      small span strong sub sup time tt ul var
      action-text-attachment figure figcaption
    ]

    ATTRIBUTES = %w[
      abbr alt cite class datetime height href lang name src title width
      xml:lang sgid content-type url filename filesize previewable
      presentation caption content
    ]

    VOID_TAGS = %w[br hr img]

    def self.sanitize(html : String) : String
      fragment = Fragment.new(html.strip)
      String.build { |io| write_children(fragment.root, io) }
    end

    private def self.write_children(parent : Lexbor::Node, io : IO) : Nil
      parent.children.each { |child| write_node(child, parent, io) }
    end

    private def self.write_node(node : Lexbor::Node, parent : Lexbor::Node, io : IO) : Nil
      if node.tag_id == Lexbor::Lib::TagIdT::LXB_TAG__TEXT
        io << escape_text(node.tag_text)
        return
      end
      if node.tag_id == Lexbor::Lib::TagIdT::LXB_TAG__EM_COMMENT
        return
      end

      name = node.tag_name.downcase
      if TAGS.includes?(name)
        io << '<' << name
        node.attributes.each do |key, value|
          next unless ATTRIBUTES.includes?(key)
          io << ' ' << key << "=\"" << escape_attr(value) << '"'
        end
        io << '>'
        unless VOID_TAGS.includes?(name)
          write_children(node, io)
          io << "</" << name << '>'
        end
      else
        # unwrap: keep children, no tag
        write_children(node, io)
        io << '\n' if unwrap_artifact?(node, parent)
      end
    end

    # libxml2 keeps a trailing "\n" when an unwrapped SCRIPT/STYLE node
    # was the last element child of an allowed element (not the fragment
    # root) with preceding content (oracle cases sz_script / rt_to_s_san;
    # unwrapped custom tags lose the newline — verified against 8.1.4).
    private def self.unwrap_artifact?(node : Lexbor::Node, parent : Lexbor::Node) : Bool
      name = node.tag_name.downcase
      return false unless name == "script" || name == "style"
      return false if parent.tag_name.downcase == "body" # fragment root
      seen_target = false
      preceding = false
      element_after_target = false
      parent.children.each do |c|
        if c.element == node.element
          seen_target = true
          next
        end
        preceding = true unless seen_target
        element_after_target = true if seen_target && c.tag_id != Lexbor::Lib::TagIdT::LXB_TAG__TEXT
      end
      # the unwrapped node is the last element child, with a preceding sibling
      seen_target && preceding && !element_after_target
    end

    private def self.escape_text(text : String) : String
      text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
    end

    private def self.escape_attr(value : String) : String
      escape_text(value).gsub('"', "&quot;")
    end
  end
end
