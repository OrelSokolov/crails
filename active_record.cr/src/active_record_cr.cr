require "db"
require "pg"
require "yaml"
require "json"
require "active_support_cr"

require "./connection"
require "./relation"
require "./base"

module ActiveRecord
  VERSION = "0.1.0"

  # Union of all attribute types (query args use DB::Any).
  alias Value = Nil | Bool | Int64 | Float64 | String | Time | JSON::Any |
                Array(String) | Array(Int64) | Bytes | PG::Numeric
end
