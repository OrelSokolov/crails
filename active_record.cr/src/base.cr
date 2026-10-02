# ActiveRecord::Base — read-side core (P0 slice for the datalake).
#
# Codegen: every model subclass is registered via `macro inherited`;
# a top-level `macro finished` reopens it at end of program and splices
# attribute methods generated from db/schema.yml via `{{ run(...) }}`
# (see codegen_runner.cr).

module ActiveRecord
  class RecordNotFound < Exception
  end

  MODELS = [] of TypeNode

  class Base
    macro inherited
      {% ActiveRecord::MODELS << @type %}
    end

    property id : Int64?
    property? new_record = true

    def persisted? : Bool
      !new_record?
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
    # cols: [["name", "CrystalType", is_bool?], ...]
    macro ar_codegen(cols)
      {% for c in cols %}
        @{{c[0].id}} : {{c[1].id}}?

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
      {% end %}

      def initialize(*, {% for c in cols %} {% if c[3] %} {{c[0].id}} : {{c[1].id}}? = nil, {% end %} {% end %})
        {% for c in cols %}
          {% if c[3] %}@{{c[0].id}} = {{c[0].id}}{% end %}
        {% end %}
      end

      def self.__from_row(rs : DB::ResultSet) : self
        record = new
        record.id = rs.read(Int64?)
        {% for c in cols %}
          record.{{c[0].id}} = rs.read({{c[1].id}}?)
        {% end %}
        record.new_record = false
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
    end
  end

  # End-of-program codegen: attribute methods + class query API per model.
  macro finished
    {% for t in ActiveRecord::MODELS %}
      {% unless t.abstract? %}
        {% class_name = t.name.split("::").last %}
        {% runner = __DIR__ + "/codegen_runner.cr" %}
        class ::{{ t.stringify.id }}
          {{ run(runner, class_name).id }}

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
        end
      {% end %}
    {% end %}
  end
end
