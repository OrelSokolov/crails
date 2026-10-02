# ar_schema_dump: dumps the public schema of the connected database into
# db/schema.yml (the codegen_runner input).
#
#   DATABASE_URL=postgres://... bin/ar_schema_dump [out_path]

require "db"
require "pg"
require "yaml"

url = ARGV[0]? || ENV["DATABASE_URL"]? || abort "usage: ar_schema_dump [DATABASE_URL] [out.yml]"
out_path = ARGV[1]? || "db/schema.yml"

DB.open(url) do |db|
  rows = db.query_all(<<-SQL, as: {String, String, String, String, String?})
    SELECT c.table_name, c.column_name, c.udt_name, c.is_nullable, c.column_default
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.table_schema = 'public' AND t.table_type = 'BASE TABLE'
    ORDER BY c.table_name, c.ordinal_position
  SQL

  tables = {} of String => Hash(String, Array(Hash(String, String?)))
  rows.each do |(table, column, udt, nullable, default)|
    entry = {"name" => column, "type" => udt, "nullable" => nullable, "default" => default}
    tables[table] ||= {"columns" => [] of Hash(String, String?)}
    tables[table]["columns"] << entry
  end

  Dir.mkdir_p(File.dirname(out_path)) unless File.dirname(out_path) == "."
  File.write(out_path, YAML.dump(tables))
  puts "dumped #{tables.size} tables -> #{out_path}"
end
