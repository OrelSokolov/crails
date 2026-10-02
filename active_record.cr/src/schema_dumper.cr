# Schema dump → db/schema.yml (the codegen_runner input).
# Library twin of bin/ar_schema_dump (schema_dump_cli.cr); used by
# `crails db:migrate` / `crails db:schema:dump` via the generated runner.

require "yaml"

module ActiveRecord
  module SchemaDumper
    def self.dump_to_file(path : String = "db/schema.yml") : Int32
      rows = Base.connection.query_all(<<-SQL, as: {String, String, String, String, String?})
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

      Dir.mkdir_p(File.dirname(path)) unless File.dirname(path) == "."
      File.write(path, YAML.dump(tables))
      tables.size
    end
  end
end
