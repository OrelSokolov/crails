# Minimal ActiveSupport core_ext slice (Iteration 0).
# Full port plan: ../PLAN.md — blank?/present?/presence/try now,
# Duration/Inflector/etc. in later phases.

class Object
  def blank? : Bool
    false
  end

  def present? : Bool
    !blank?
  end

  def presence : self?
    present? ? self : nil
  end

  # nil.try stays nil, like in Rails.
  def try(&)
    yield self
  end
end

struct Nil
  def blank? : Bool
    true
  end

  def present? : Bool
    false
  end

  # Block is never called (matching Rails nil.try).
  def try(&) : Nil
    nil
  end
end

module Indexable
  def blank? : Bool
    empty?
  end
end

class Hash
  def blank? : Bool
    empty?
  end
end
