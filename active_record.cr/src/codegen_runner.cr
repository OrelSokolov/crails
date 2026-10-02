# {{ run }} helper: prints ActiveRecord model code for one table.
# Invoked from base.cr as `run("#{__DIR__}/codegen_runner.cr", class_name)`.
# Reads db/schema.yml (or CRAILS_SCHEMA) — dumped by `ar_schema_dump`.
#
# Attribute generation is delegated to the `ar_codegen` macro in base.cr
# (string column names keep PostgreSQL keywords like `until` working).

require "yaml"

# Underscore + pluralize (mirror of ActiveSupport::Inflector; this runner
# is a standalone program and cannot call runtime code).
def underscore(camel : String) : String
  camel.gsub(/::/, "/")
    .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1_\\2")
    .gsub(/([a-z\d])([A-Z])/, "\\1_\\2")
    .tr("-", "_")
    .downcase
end

PLURAL_RULES = {
  /(s)tudy$/              => "\\1tudies",
  /(matr)ix$/             => "\\1ices",
  /(vert|ind)ex$/         => "\\1ices",
  /(x|ch|ss|sh)$/         => "\\1es",
  /([^aeiouy]|qu)y$/      => "\\1ies",
  /(?:([^f])fe|([lr])f)$/ => "\\1\\2ves",
  /(hive)$/               => "\\1s",
  /([^o])o$/              => "\\1oes",
  /(.*)$/                 => "\\1s",
}

UNCOUNTABLES = %w(equipment information rice money species series fish sheep jeans police)
IRREGULARS = {
  "person" => "people",
  "man"    => "men",
  "child"  => "children",
  "sex"    => "sexes",
  "move"   => "moves",
}

def pluralize(word : String) : String
  lower = word.downcase
  return word if UNCOUNTABLES.includes?(lower)
  if irregular = IRREGULARS[lower]?
    return irregular
  end
  PLURAL_RULES.each do |rule, replacement|
    next unless word.match(rule)
    return word.sub(rule, replacement)
  end
  word + "s"
end

CLASS_NAME = ARGV[0]? || abort "codegen_runner: class name argument required"
TABLE = (ARGV[1]? && !ARGV[1].empty?) ? ARGV[1] : pluralize(underscore(CLASS_NAME))
SCHEMA_PATH = ENV["CRAILS_SCHEMA"]? || "db/schema.yml"

def crystal_type(udt : String) : String
  case udt
  when "int2", "int4", "int8"             then "Int64"
  when "float4", "float8"                  then "Float64"
  when "numeric"                           then "PG::Numeric"
  when "bool"                              then "Bool"
  when "date", "timestamp", "timestamptz"  then "Time"
  when "json", "jsonb"                     then "JSON::Any"
  when "bytea"                             then "Bytes"
  when "_text", "_varchar", "_bpchar", "_char", "_uuid", "_name" then "Array(String)"
  when "_int2", "_int4", "_int8"           then "Array(Int64)"
  when "_float4", "_float8"                then "Array(Float64)"
  when "_bool"                             then "Array(Bool)"
  else "String"
  end
end

code = [] of String

code << "def self.table_name : String"
code << "  #{TABLE.inspect}"
code << "end"

# Crystal keywords that cannot be used as named-argument parameter names
# (getter/setter still work — see ar_codegen).
RESERVED_PARAMS = %w(
  abstract alias begin break case class def do else elsif end enum ensure
  extend false for fun if in is_a? lib macro module next nil of out
  pointerof private protected require rescue respond_to? return select
  self sizeof struct super then true type typeof union until when while
  with yield
)

cols = [] of {name: String, type: String, bool: Bool, kw_ok: Bool, default: String}

if File.exists?(SCHEMA_PATH)
  schema = YAML.parse(File.read(SCHEMA_PATH))
  table = schema[TABLE]?
  abort "codegen_runner: table #{TABLE} not found in #{SCHEMA_PATH}" unless table
  table["columns"].as_a.each do |c|
    name = c["name"].as_s
    next if name == "id"
    type = c["type"].as_s
    cols << {
      name:    name,
      type:    crystal_type(type),
      bool:    type == "bool",
      kw_ok:   !RESERVED_PARAMS.includes?(name),
      default: default_literal(type, c["default"]?.try(&.as_s?)),
    }
  end
end

# Column default → Crystal literal (nil when unparsable). Keeps `changed?`
# honest for new records: Post.new(views: 1).changes → {"views"=>[0, 1]}.
def default_literal(type : String, default : String?) : String
  return "nil" if default.nil? || default.empty?
  d = default.strip
  quoted = d.match(/\A'(.*)'::/) || d.match(/\A'(.*)'\z/)
  raw = quoted ? quoted[1] : d
  case type
  when "int2", "int4", "int8"
    raw.match(/\A-?\d+\z/) ? "#{raw}_i64" : "nil"
  when "float4", "float8"
    raw.match(/\A-?\d+(\.\d+)?\z/) ? raw : "nil"
  when "bool"
    raw == "true" ? "true" : raw == "false" ? "false" : "nil"
  when "json", "jsonb"
    raw == "[]" ? "JSON.parse(\"[]\")" : raw == "{}" ? "JSON.parse(\"{}\")" : "nil"
  when "timestamp", "timestamptz", "date"
    "nil" # CURRENT_TIMESTAMP-ish defaults are not portable literals
  else
    "nil"
  end
end

names = ["id"] + cols.map(&.[:name])
code << "def self.__column_names : Array(String)"
code << "  #{names.inspect}"
code << "end"

code << "ar_codegen(#{cols.map { |c| %([#{c[:name].inspect}, #{c[:type].inspect}, #{c[:bool]}, #{c[:kw_ok]}, #{c[:default]}]) }.join(", ").insert(0, "[").insert(-1, "]")})"

code << "def to_param : String"
code << "  id.to_s"
code << "end"

code << "def inspect : String"
code << %(  parts = attributes.map { |k, v| "\#{k}: \#{v.inspect}" })
code << %(  "#<\#{self.class.name || "?"} \#{parts.join(", ")}>")
code << "end"

code << "def to_s : String"
code << "  inspect"
code << "end"

code << "def reload! : self"
code << "  fresh = self.class.find?(id.not_nil!)"
code << %(  raise ActiveRecord::RecordNotFound.new("record \#{id} gone") unless fresh)
code << %(  assign_attributes(fresh.attributes.reject { |k, _| k == "id" }))
code << "  @id = fresh.id"
code << "  self"
code << "end"

puts code.join("\n")
