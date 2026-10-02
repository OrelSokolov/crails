require "json"
require "uuid"
require "active_support_cr"

require "./serialization"
require "./test_adapter"
require "./base"

module ActiveJob
  VERSION = "0.1.0"

  # Global queue adapter (like Rails' config.active_job.queue_adapter).
  # Defaults to the test adapter; apps set their own (async/pg/inline).
  class_property adapter : Adapter = TestAdapter.new
end
