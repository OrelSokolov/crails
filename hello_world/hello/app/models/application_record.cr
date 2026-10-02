# Base class for models, like Rails' ApplicationRecord.
# Attributes are generated from db/schema.yml at compile time
# (`crails new` leaves it absent; dump one with ar_schema_dump).
abstract class ApplicationRecord < ActiveRecord::Base
end