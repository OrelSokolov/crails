# Validations: validates ... presence/length/numericality/format/uniqueness
# + custom `validate` blocks/methods. Messages are 1:1 with Rails
# (verified against oracle/expected.yml, activerecord 8.1.4).

module ActiveRecord
  class Base
    def valid? : Bool
      errors.clear
      return false unless __run_before_validation
      __run_validations
      errors.empty?
    end

    def invalid? : Bool
      !valid?
    end

    def __run_validations : Nil
    end

    # --- DSL -------------------------------------------------------------
    # validates :title, presence: true, length: {maximum: 10}
    # validates :views, numericality: {greater_than_or_equal_to: 0, ...}, allow_nil: true
    # validates :email, format: {with: /.../}, uniqueness: true
    macro validates(*columns, presence = nil, length = nil, numericality = nil,
                    format = nil, uniqueness = nil, allow_nil = false)
      {% for col in columns %}
        {% n = @type.methods.select { |m| m.name.starts_with?("validation__") }.size %}
        {% cname = col.id %}
        def validation__{{cname}}__{{n}} : Nil
          value = attributes[{{col.id.stringify}}]?
          {% if allow_nil %}
            return if value.nil?
          {% end %}

          {% if presence %}
            if value.nil? || (value.is_a?(String) && value.strip.empty?)
              errors.add({{col.id.stringify}}, "can't be blank", :blank)
            end
          {% end %}

          {% if length %}
            {% max = length[:maximum] %}
            {% min = length[:minimum] %}
            {% if max %}
              if value.is_a?(String) && value.size > {{max}}
                errors.add({{col.id.stringify}}, "is too long (maximum is {{max}} characters)", :too_long)
              end
            {% end %}
            {% if min %}
              if value.is_a?(String) && value.size < {{min}}
                errors.add({{col.id.stringify}}, "is too short (minimum is {{min}} characters)", :too_short)
              end
            {% end %}
          {% end %}

          {% if numericality %}
            {% gt = numericality[:greater_than] %}
            {% gte = numericality[:greater_than_or_equal_to] %}
            {% lt = numericality[:less_than] %}
            {% lte = numericality[:less_than_or_equal_to] %}
            case value
            when Int64, Int32, Float64
              {% if gt %}
                errors.add({{col.id.stringify}}, "must be greater than {{gt}}", :greater_than) if value.to_f <= {{gt}}.to_f
              {% end %}
              {% if gte %}
                errors.add({{col.id.stringify}}, "must be greater than or equal to {{gte}}", :greater_than_or_equal_to) if value.to_f < {{gte}}.to_f
              {% end %}
              {% if lt %}
                errors.add({{col.id.stringify}}, "must be less than {{lt}}", :less_than) if value.to_f >= {{lt}}.to_f
              {% end %}
              {% if lte %}
                errors.add({{col.id.stringify}}, "must be less than or equal to {{lte}}", :less_than_or_equal_to) if value.to_f > {{lte}}.to_f
              {% end %}
            else
              errors.add({{col.id.stringify}}, "is not a number", :not_a_number)
            end
          {% end %}

          {% if format %}
            {% pattern = format[:with] %}
            unless value.is_a?(String) && value.match({{pattern}})
              errors.add({{col.id.stringify}}, "is invalid", :invalid)
            end
          {% end %}

          {% if uniqueness %}
            unless value.nil?
              taken = self.class.where({{col.id.stringify}} + " = ?", value).exists?
              if taken && !(persisted? && __original_attributes[{{col.id.stringify}}]? == value)
                errors.add({{col.id.stringify}}, "has already been taken", :taken)
              end
            end
          {% end %}
          nil
        end
      {% end %}
    end

    # Custom validations: `validate :check_name` or `validate do ... end`.
    macro validate(method_name = nil, &block)
      {% n = @type.methods.select { |m| m.name.starts_with?("validation__") }.size %}
      {% if method_name %}
        def validation__custom__{{n}} : Nil
          {{method_name.id}}
          nil
        end
      {% else %}
        def validation__custom__{{n}} : Nil
          {{block.body}}
          nil
        end
      {% end %}
    end

    # %(...) placeholder rendering for error messages with %{count} etc.
    def self.__render_message(template : String, **vars) : String
      result = template
      vars.each { |k, v| result = result.gsub("%{#{k}}", v.to_s) }
      result
    end
  end
end
