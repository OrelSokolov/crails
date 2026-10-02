# ActiveRecord::Base — read-side core (P0 slice for the datalake).
#
# Codegen: every model subclass is registered via `macro inherited`;
# a top-level `macro finished` reopens it at end of program and splices
# attribute methods generated from db/schema.yml via `{{ run(...) }}`
# (see codegen_runner.cr).

module ActiveRecord
  class RecordNotFound < Exception
  end

  class RecordInvalid < Exception
    getter record

    def initialize(@record : Base)
      super("Validation failed: #{@record.errors.full_messages.join(", ")}")
    end
  end

  class RecordNotSaved < Exception
  end

  class RecordNotUnique < Exception
  end

  MODELS = [] of TypeNode

  # Compile-time registry of `set_table_name` overrides, filled by the macro.
  # (Constants defined in subclasses are not yet visible from `macro finished`,
  # so a registry is used instead of a `__TABLE_NAME__` constant lookup.)
  TABLE_OVERRIDES = [] of Nil

  class Base
    macro inherited
      {% ActiveRecord::MODELS << @type %}
    end

    # Explicit table name override (before codegen):
    #   class LegacyPost < ActiveRecord::Base
    #     set_table_name "posts"
    #   end
    macro set_table_name(name)
      {% ActiveRecord::TABLE_OVERRIDES << {@type.name.stringify, name} %}
    end

    property id : Int64?
    property? new_record = true
    property? destroyed = false

    # Errors from the last validation run (see validations.cr).
    property errors = Errors.new

    @original_attributes : Hash(String, Value)?
    @previous_changes : Hash(String, Tuple(Value, Value)) = {} of String => Tuple(Value, Value)

    def persisted? : Bool
      !new_record? && !destroyed?
    end

    # dirty API ------------------------------------------------------------
    # `changes` etc. live in persistence.cr; they compare `attributes`
    # against the snapshot taken on load/save (`@original_attributes`).

    def __original_attributes : Hash(String, Value)
      @original_attributes || {} of String => Value
    end

    def __snapshot_original! : Nil
      @original_attributes = attributes.dup
    end

    def __previous_changes! (changes) : Nil
      @previous_changes = changes
    end

    def saved_changes : Hash(String, Tuple(Value, Value))
      @previous_changes
    end

    def has_changes_to_save? : Bool
      changed?
    end

    def ==(other : self) : Bool
      !id.nil? && !other.id.nil? && id == other.id
    end

    def hash(hasher)
      id.hash(hasher)
    end

    # Attribute codegen from schema.yml (called with string column names
    # so PostgreSQL keywords like `until` stay 1:1 — def names are built
    # at the AST level and never re-parsed).
    # cols: [["name", "CrystalType", is_bool?, kw_ok?, default_lit], ...]
    macro ar_codegen(cols)
      {% for c in cols %}
        @{{c[0].id}} : {{c[1].id}}? = {{c[4]}}

        def {{c[0].id}} : {{c[1].id}}?
          @{{c[0].id}}
        end

        def {{c[0].id}}=(value : {{c[1].id}}?)
          @{{c[0].id}} = value
        end

        {% if c[2] %}
          def {{c[0].id}}? : Bool
            !!@{{c[0].id}}
          end
        {% end %}

        def {{c[0].id}}_was : ::ActiveRecord::Value
          changed_attribute?({{c[0]}}) ? __original_attributes[{{c[0]}}] : @{{c[0].id}}.as(::ActiveRecord::Value)
        end

        def {{c[0].id}}_changed? : Bool
          attribute_changed?({{c[0]}}, @{{c[0].id}})
        end

        def will_save_change_to_{{c[0].id}}? : Bool
          {{c[0].id}}_changed?
        end

        def {{c[0].id}}_previously_changed? : Bool
          saved_changes.has_key?({{c[0]}})
        end
      {% end %}

      {% params = [] of Nil %}
      {% for c in cols %}{% if c[3] %}{% params << c %}{% end %}{% end %}
      {% if params.empty? %}
        def initialize
        end
      {% else %}
        def initialize(*, {% for c in params %} {{c[0].id}} : {{c[1].id}}? = {{c[4]}}, {% end %})
          {% for c in params %}@{{c[0].id}} = {{c[0].id}};{% end %}
        end
      {% end %}

      def self.__from_row(rs : DB::ResultSet) : self
        record = new
        record.id = rs.read(Int64?)
        {% for c in cols %}
          {% if c[1] == "Int64" %}
            # int2/int4 columns decode as Int32 — widen to Int64
            record.{{c[0].id}} = rs.read(Int32 | Int64 | Nil).try(&.to_i64)
          {% else %}
            record.{{c[0].id}} = rs.read({{c[1].id}}?)
          {% end %}
        {% end %}
        record.new_record = false
        record.__snapshot_original!
        record
      end

      def attributes : Hash(String, ActiveRecord::Value)
        attrs = {} of String => ActiveRecord::Value
        attrs["id"] = @id
        {% for c in cols %}
          attrs[{{c[0]}}] = @{{c[0].id}}
        {% end %}
        attrs
      end

      def [](name : String) : ActiveRecord::Value
        case name
        when "id" then @id
        {% for c in cols %}
          when {{c[0]}} then @{{c[0].id}}
        {% end %}
        else
          raise ArgumentError.new("unknown attribute #{name} for #{self.class}")
        end
      end

      def assign_attributes(values : Hash(String, ActiveRecord::Value)) : Nil
        values.each do |name, value|
          case name
          {% for c in cols %}
            when {{c[0]}} then @{{c[0].id}} = value.as?({{c[1].id}})
          {% end %}
          else
            raise ArgumentError.new("unknown attribute #{name} for #{self.class}")
          end
        end
      end

      def self.__column_defaults : Hash(String, ActiveRecord::Value)
        defaults = {} of String => ActiveRecord::Value
        {% for c in cols %}
          {% unless c[4] == "nil" %}
            defaults[{{c[0]}}] = {{c[4].id}}.as(ActiveRecord::Value)
          {% end %}
        {% end %}
        defaults
      end
    end
  end

  # End-of-program codegen: attribute methods + class query API per model.
  macro finished
    {% for t in ActiveRecord::MODELS %}
      {% unless t.abstract? %}
        {% class_name = t.name.split("::").last %}
        {% custom_table = nil %}
        {% for pair in ActiveRecord::TABLE_OVERRIDES %}
          {% if pair[0] == t.name.stringify %}
            {% custom_table = pair[1] %}
          {% end %}
        {% end %}
        {% table_arg = custom_table || "" %}
        {% runner = __DIR__ + "/codegen_runner.cr" %}
        class ::{{ t.stringify.id }}
          {{ run(runner, class_name, table_arg).id }}

          def self.all : ::ActiveRecord::Relation(self)
            ::ActiveRecord::Relation(self).new(self)
          end

          def self.where(condition : String, *args) : ::ActiveRecord::Relation(self)
            all.where(condition, *args)
          end

          def self.where(**opts) : ::ActiveRecord::Relation(self)
            all.where(**opts)
          end

          def self.not(**opts) : ::ActiveRecord::Relation(self)
            all.not(**opts)
          end

          def self.order(*cols : String | Symbol) : ::ActiveRecord::Relation(self)
            all.order(*cols)
          end

          def self.order(**opts) : ::ActiveRecord::Relation(self)
            all.order(**opts)
          end

          def self.limit(n : Int) : ::ActiveRecord::Relation(self)
            all.limit(n)
          end

          def self.offset(n : Int) : ::ActiveRecord::Relation(self)
            all.offset(n)
          end

          def self.count : Int64
            all.count
          end

          def self.exists? : Bool
            all.exists?
          end

          def self.exists?(id : Int64 | Int32) : Bool
            all.where(id: id).exists?
          end

          def self.take : self?
            all.take
          end

          def self.first : self?
            all.first
          end

          def self.first! : self
            all.first!
          end

          def self.last : self?
            all.last
          end

          def self.pluck(col : String | Symbol) : Array(ActiveRecord::Value)
            all.pluck(col)
          end

          def self.ids : Array(Int64)
            all.ids
          end

          def self.find(id : Int64 | Int32) : self
            pk = id.to_i64
            find?(pk) || raise ActiveRecord::RecordNotFound.new(
              "Couldn't find #{self} with 'id'=#{pk}")
          end

          def self.find?(id : Int64 | Int32) : self?
            all.where(id: id.to_i64).first
          end

          def self.find_by(**opts) : self?
            all.where(**opts).first
          end

          def self.find_by!(**opts) : self
            find_by(**opts) || raise ActiveRecord::RecordNotFound.new(
              "Couldn't find #{self} with #{opts.map { |k, v| "#{k}=#{v}" }.join(" ")}")
          end

          def self.find_each(batch_size : Int32 = 1000, & : self ->) : Nil
            all.find_each(batch_size) { |record| yield record }
          end

          # --- hook runners assembled from prefixed methods -----------------
          def __run_validations : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("validation__") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_before_validation : Bool
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("before_validation__cb_") %}
                return false unless {{ m.name.id }}
              {% end %}
            {% end %}
            true
          end

          def __run_before_save : Bool
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("before_save__cb_") %}
                return false unless {{ m.name.id }}
              {% end %}
            {% end %}
            true
          end

          def __run_before_destroy : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("before_destroy__cb_") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_after_create : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("after_create__cb_") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_after_update : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("after_update__cb_") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_after_save : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("after_save__cb_") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_after_destroy : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("after_destroy__cb_") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_dependents : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("dependent__cb_") %}{{ m.name.id }}{% end %}
            {% end %}
            nil
          end

          def __run_after_commit(event : Symbol) : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("after_commit__cb_") %}{{ m.name.id }}(event){% end %}
            {% end %}
            nil
          end

          def __run_after_rollback(event : Symbol) : Nil
            {% for m in t.methods %}
              {% if m.name.stringify.starts_with?("after_rollback__cb_") %}{{ m.name.id }}(event){% end %}
            {% end %}
            nil
          end
        end
      {% end %}
    {% end %}
  end
end
