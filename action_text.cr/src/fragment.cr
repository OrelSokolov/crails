# Fragment: wraps an HTML fragment parsed by lexbor (the gem wraps a
# Nokogiri::HTML5::DocumentFragment). `root` is the <body> node; its
# children hold the fragment content, matching Nokogiri fragment
# serialization byte for byte (verified against the oracle).
require "lexbor"

module ActionText
  class Fragment
    getter parser : Lexbor::Parser
    getter root : Lexbor::Node

    def self.from_html(html : String) : Fragment
      # Nokogiri path strips the input before parsing.
      new(html.strip)
    end

    def initialize(html : String)
      @parser = Lexbor::Parser.new(html)
      @root = parser.body || raise(Lexbor::EmptyNodeError.new("no <body> in fragment"))
    end

    def to_html : String
      root.inner_html
    end

    def to_s : String
      to_html
    end
  end
end
