# CRails console bootstrap — loads the app WITHOUT starting the
# server; used by `crails console` (every line re-runs this file).
require "railties_cr"
require "active_record_cr"
require "../config/application"
require "../app/models/**"
require "../app/controllers/**"
require "../config/routes"

if (url = ENV["DATABASE_URL"]?)
  ActiveRecord::Base.establish_connection(url)
elsif File.exists?("config/database.yml")
  ActiveRecord::Base.establish_connection_from_yaml(
    "config/database.yml", CRails.env.to_s.downcase)
end