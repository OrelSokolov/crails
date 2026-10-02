# Minimal Inflector slice (needed by active_record.cr for class → table
# naming). Full port (humanize, titleize, parameterize, ...) later per
# active_support.cr/PLAN.md.

module ActiveSupport
  module Inflector
    PLURAL_RULES = {
      /(s)tudy$/            => "\\1tudies",
      /(matr)ix$/           => "\\1ices",
      /(vert|ind)ex$/       => "\\1ices",
      /(x|ch|ss|sh)$/       => "\\1es",
      /([^aeiouy]|qu)y$/    => "\\1ies",
      /(?:([^f])fe|([lr])f)$/ => "\\1\\2ves",
      /(hive)$/             => "\\1s",
      /([^o])o$/            => "\\1oes",
      /(.*)$/               => "\\1s",
    }

    UNCOUNTABLES = %w(equipment information rice money species series fish sheep jeans police)
    IRREGULARS = {
      "person" => "people",
      "man"    => "men",
      "child"  => "children",
      "sex"    => "sexes",
      "move"   => "moves",
    }

    def self.pluralize(word : String) : String
      lower = word.downcase
      return word if UNCOUNTABLES.includes?(lower)
      if irregular = IRREGULARS[lower]?
        return word.ends_with?(word.capitalize) ? irregular.capitalize : irregular
      end
      PLURAL_RULES.each do |rule, replacement|
        match = word.match(rule)
        next unless match
        return word.sub(rule, replacement)
      end
      word + "s"
    end

    def self.underscore(camel : String) : String
      camel.gsub(/::/, "/")
        .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
        .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
        .tr("-", "_")
        .downcase
    end

    def self.camelize(term : String) : String
      term.split("/").map do |part|
        part.split(/[_\-]/).map(&.capitalize).join
      end.join("::")
    end
  end
end

class String
  def pluralize : String
    ActiveSupport::Inflector.pluralize(self)
  end

  def underscore : String
    ActiveSupport::Inflector.underscore(self)
  end

  def camelize : String
    ActiveSupport::Inflector.camelize(self)
  end

  def tableize : String
    underscore.pluralize
  end
end
