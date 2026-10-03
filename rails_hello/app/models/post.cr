# ApplicationRecord-style indirection is not supported by the AR codegen
# (each model maps to its own table) — models inherit Base directly.
class Post < ActiveRecord::Base
  validates :title, presence: true, length: {maximum: 140}
end

