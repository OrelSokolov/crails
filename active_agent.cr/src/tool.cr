# Tool — the CRM-facing contract (the whole point of the framework).
# A tool is typed Crystal code the agent's LLM may invoke: the model
# returns a tool name + JSON arguments, the framework parses them into
# compile-time-known types and calls YOUR code. The tool surface is the
# attack surface — same as a REST API — and it is fully developer-owned.
#
#   class CustomerSearch
#     include ActiveAgent::Tool
#     description "Найти клиента по телефону или имени."   # mandatory (ACI)
#     input phone : String?, name : String?
#
#     def call : ToolResult
#       ToolResult.ok(Customer.find_by(phone: phone).to_public_json)
#     end
#   end
#
# `input` generates, per field: the property, the JSON-Schema entry for
# function calling (compile-time, no runtime reflection), and the typed
# extraction of the LLM's JSON arguments (missing required field raises
# before any tool code runs). Supported types: String, Int32, Int64,
# Float64, Bool, Array(String) — each nilable with `?`.

module ActiveAgent
  class ToolResult
    getter ok : Bool
    getter content : String # serialized payload sent back to the model

    def initialize(@ok, @content)
    end

    def self.ok(data : String) : ToolResult
      new(true, data)
    end

    def self.ok(data) : ToolResult
      new(true, data.to_json)
    end

    def self.error(message : String) : ToolResult
      new(false, message)
    end
  end

  module Tool
    # Runtime half of the schema builder (types are compile-known —
    # the macro passes them as strings; see #input).
    def self.property_schema(type_string : String) : JSON::Any
      case type_string
      when "String", "String?"
        JSON::Any.new({"type" => JSON::Any.new("string")} of String => JSON::Any)
      when "Int32", "Int32?", "Int64", "Int64?"
        JSON::Any.new({"type" => JSON::Any.new("integer")} of String => JSON::Any)
      when "Float64", "Float64?"
        JSON::Any.new({"type" => JSON::Any.new("number")} of String => JSON::Any)
      when "Bool", "Bool?"
        JSON::Any.new({"type" => JSON::Any.new("boolean")} of String => JSON::Any)
      when "Array(String)", "Array(String)?"
        JSON::Any.new({"type" => JSON::Any.new("array"),
                       "items" => JSON::Any.new({"type" => JSON::Any.new("string")} of String => JSON::Any)} of String => JSON::Any)
      else
        raise ArgumentError.new("Unsupported Tool input type: #{type_string}")
      end
    end

    # Class-level API lands on the including type (class methods are
    # not inherited via include — the standard macro-included lift).
    macro included
      # Wire name: CustomerSearch → "customer_search" (matches MCP too).
      def self.tool_name : String
        {{ @type.name.split("::").last.underscore }}
      end

      # The LLM-facing docstring — mandatory. "Write it like a docstring
      # for a junior developer" (Anthropic, tool ACI). Overridden by
      # the `description` macro.
      def self.__description : String
        raise NotImplementedError.new(
          "#{self} needs a description — it is the model's only manual")
      end

      # (name, type-string, optional?) — overridden by `input`.
      def self.__fields : Array({String, String, Bool})
        [] of {String, String, Bool}
      end

      def self.__build(payload : JSON::Any) : self
        {% if @type.methods.any? { |m| m.name.stringify == "__fields" && !m.body.is_a?(Nop) } %}
          # reachable only when input-less tool forgot `input`
        {% end %}
        raise NotImplementedError.new("#{self} needs `input` fields " \
                                      "(or a custom __build)")
      end

      # Full function-calling schema (compile-time fields, assembled here).
      def self.schema : JSON::Any
        fields = __fields
        props = {} of String => JSON::Any
        required = [] of String
        fields.each do |(fname, type_string, optional)|
          props[fname] = ActiveAgent::Tool.property_schema(type_string)
          required << fname unless optional
        end
        obj = {"type"       => JSON::Any.new("object"),
               "properties" => JSON::Any.new(props)} of String => JSON::Any
        obj["required"] = JSON::Any.new(required.map { |r| JSON::Any.new(r) }) unless required.empty?
        obj["additionalProperties"] = JSON::Any.new(false)
        JSON::Any.new(obj)
      end
    end

    # The LLM-facing docstring.
    macro description(text)
      def self.__description : String
        {{ text }}
      end
    end

    # input phone : String?, name : String?
    macro input(*decls)
      {% for d in decls %}
        @{{ d.var.id }} : {{ d.type }}
      {% end %}

      def initialize(
        {% for d in decls %}
          @{{ d.var.id }} : {{ d.type }}{% if d.type.stringify.includes?("Nil") %} = nil{% end %},
        {% end %}
      )
      end

      {% for d in decls %}
        def {{ d.var.id }} : {{ d.type }}
          @{{ d.var.id }}
        end
      {% end %}

      # (name, type-string, optional?) — assembled into #schema.
      # "String?" arrives from the parser as "(String | ::Nil)": normalize.
      def self.__fields : Array({String, String, Bool})
        [
          {% for d in decls %}
            {
              {{ d.var.stringify }},
              {% t = d.type.stringify.gsub(/ \| (::)?Nil/, "?").gsub(/^\(|\)$/, "") %}
              {{ t }},
              {{ d.type.stringify.includes?("Nil") }},
            },
          {% end %}
        ]
      end

      # Typed extraction of the LLM's JSON arguments. Required fields
      # missing/wrong-typed raise before any tool code runs.
      def self.__build(payload : JSON::Any) : self
        {% if decls.size == 0 %}
          new
        {% else %}
          new(
            {% for d in decls %}
              {% t = d.type.stringify.gsub(/ \| (::)?Nil/, "?").gsub(/^\(|\)$/, "") %}
              {% key = d.var.stringify %}
              {% if t == "String" %}ActiveAgent::Tool.req_string({{ key }}, payload),{% end %}
              {% if t == "String?" %}payload[{{ key }}]?.try(&.as_s?),{% end %}
              {% if t == "Int32" %}ActiveAgent::Tool.req_int({{ key }}, payload).to_i32,{% end %}
              {% if t == "Int32?" %}payload[{{ key }}]?.try(&.as_i?).try(&.to_i32),{% end %}
              {% if t == "Int64" %}ActiveAgent::Tool.req_int({{ key }}, payload),{% end %}
              {% if t == "Int64?" %}payload[{{ key }}]?.try(&.as_i?),{% end %}
              {% if t == "Float64" %}ActiveAgent::Tool.req_float({{ key }}, payload),{% end %}
              {% if t == "Float64?" %}payload[{{ key }}]?.try(&.as_f?),{% end %}
              {% if t == "Bool" %}ActiveAgent::Tool.req_bool({{ key }}, payload),{% end %}
              {% if t == "Bool?" %}payload[{{ key }}]?.try(&.as_bool?),{% end %}
              {% if t == "Array(String)" %}ActiveAgent::Tool.req_str_array({{ key }}, payload),{% end %}
              {% if t == "Array(String)?" %}payload[{{ key }}]?.try { |a| a.map(&.as_s) },{% end %}
              {% supported = ["String", "String?", "Int32", "Int32?", "Int64", "Int64?", "Float64", "Float64?", "Bool", "Bool?", "Array(String)", "Array(String)?"] %}
              {% unless supported.includes?(t) %}{% raise "Unsupported Tool input type #{t} for #{key}" %}{% end %}
            {% end %}
          )
        {% end %}
      end
    end

    # --- typed extraction helpers (compile-known keys/types) ------------

    def self.req_string(key : String, payload : JSON::Any) : String
      payload[key]?.try(&.as_s?) ||
        raise ArgumentError.new("Tool argument '#{key}' (String) missing or wrong type")
    end

    def self.req_int(key : String, payload : JSON::Any) : Int64
      value = payload[key]?.try(&.as_i?) ||
        raise ArgumentError.new("Tool argument '#{key}' (Integer) missing or wrong type")
      value.to_i64
    end

    def self.req_float(key : String, payload : JSON::Any) : Float64
      payload[key]?.try(&.as_f?) ||
        raise ArgumentError.new("Tool argument '#{key}' (Number) missing or wrong type")
    end

    def self.req_bool(key : String, payload : JSON::Any) : Bool
      payload[key]?.try(&.as_bool?) ||
        raise ArgumentError.new("Tool argument '#{key}' (Boolean) missing or wrong type")
    end

    def self.req_str_array(key : String, payload : JSON::Any) : Array(String)
      payload[key]?.try(&.as_a?).try(&.map(&.as_s)) ||
        raise ArgumentError.new("Tool argument '#{key}' (Array(String)) missing or wrong type")
    end

    # The tool body. Receives nothing — inputs are typed properties.
    def call : ToolResult
      raise NotImplementedError.new("#{self} must define #call")
    end
  end
end
