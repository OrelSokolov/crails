# Associations: belongs_to / has_many / has_one (+ dependent: :destroy).
#
# P0 notes: associated model class is resolved by convention
# (`comments` → `Comment`); `foreign_key:` overrides the default
# ("<singularized owner>_id" — computed as downcased class name, pass
# foreign_key for multi-word class names).

module ActiveRecord
  # Proxy returned by has_many: query methods + build/create/<<.
  struct CollectionProxy(T)
    include Enumerable(T)

    getter owner_id : Int64?
    getter foreign_key : String
    getter model : T.class

    def initialize(@model : T.class, @owner_id : Int64?, @foreign_key : String)
    end

    private def scope : Relation(T)
      if oid = @owner_id
        @model.where(%("#{@foreign_key}" = ?), oid)
      else
        @model.all
      end
    end

    def each(& : T ->) : Nil
      scope.each { |r| yield r }
    end

    def count : Int64
      scope.count
    end

    def size : Int64
      count
    end

    def empty? : Bool
      !scope.exists?
    end

    def ids : Array(Int64)
      scope.ids
    end

    def pluck(col : String | Symbol) : Array(Value)
      scope.pluck(col)
    end

    def order(*cols : String | Symbol) : Relation(T)
      scope.order(*cols)
    end

    def where(condition : String, *args) : Relation(T)
      scope.where(condition, *args)
    end

    def build(values : Hash(String, Value) = {} of String => Value) : T
      record = @model.new
      record.assign_attributes(values)
      record.assign_attributes({@foreign_key => @owner_id.as(Value)})
      record
    end

    def create(values : Hash(String, Value) = {} of String => Value) : T
      record = build(values)
      record.save
      record
    end

    def create!(values : Hash(String, Value) = {} of String => Value) : T
      record = build(values)
      record.save || raise RecordInvalid.new(record)
      record
    end

    def <<(record : T) : self
      record.assign_attributes({@foreign_key => @owner_id.as(Value)})
      record.save
      self
    end

    def destroy_all : Nil
      scope.each(&.destroy)
    end

    def delete_all : Nil
      if oid = @owner_id
        Base.__session.exec(
          "DELETE FROM #{@model.quoted_table_name} WHERE \"#{@foreign_key}\" = $1",
          [oid])
      end
    end
  end

  class Base
    macro belongs_to(name, foreign_key = nil, class_name = nil, optional = true)
      {% fk = (foreign_key || "#{name.id}_id").id %}
      {% klass = (class_name || name.id.stringify.capitalize).id %}

      def {{name.id}} : {{klass}}?
        {{fk.id}}.nil? ? nil : {{klass}}.find?({{fk.id}}.not_nil!)
      end

      # Rails: assigning the associated object sets the FK (unsaved).
      def {{name.id}}=(record : {{klass}})
        @{{fk.id}} = record.id
        record
      end

      def build_{{name.id}}(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : {{klass}}
        record = {{klass}}.new
        record.assign_attributes(values)
        record
      end

      def create_{{name.id}}(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : {{klass}}
        record = build_{{name.id}}(values)
        record.save
        @{{fk.id}} = record.id
        record
      end

      def create_{{name.id}}!(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : {{klass}}
        record = build_{{name.id}}(values)
        record.save || raise RecordInvalid.new(record)
        @{{fk.id}} = record.id
        record
      end
    end

    macro has_many(name, dependent = nil, foreign_key = nil, class_name = nil)
      {% owner_base = @type.name.split("::").last.downcase %}
      {% owner_fk = (foreign_key || (owner_base + "_id")) %}
      {% klass = (class_name || name.id.stringify.capitalize.gsub(/s$/, "")).id %}

      def {{name.id}} : ::ActiveRecord::CollectionProxy({{klass}})
        ::ActiveRecord::CollectionProxy({{klass}}).new({{klass}}, @id, {{owner_fk}})
      end

      def {{(name.id.stringify.gsub(/s$/, "") + "_ids").id}} : Array(Int64)
        {{name.id}}.ids
      end

      {% if dependent == :destroy %}
        __dependent_destroy {{name.id}}.destroy_all
      {% elsif dependent == :delete_all %}
        __dependent_destroy {{name.id}}.delete_all
      {% end %}
    end

    macro has_one(name, dependent = nil, foreign_key = nil, class_name = nil)
      {% owner_base = @type.name.split("::").last.downcase %}
      {% owner_fk = (foreign_key || (owner_base + "_id")) %}
      {% klass = (class_name || name.id.stringify.capitalize).id %}

      def {{name.id}} : {{klass}}?
        {{klass}}.where({{owner_fk}} + " = ?", @id).first
      end

      def build_{{name.id}}(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : {{klass}}
        record = {{klass}}.new
        record.assign_attributes(values)
        record.assign_attributes({ {{owner_fk}} => @id.as(::ActiveRecord::Value) })
        record
      end

      def create_{{name.id}}(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : {{klass}}
        record = build_{{name.id}}(values)
        record.save
        record
      end

      def create_{{name.id}}!(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : {{klass}}
        record = build_{{name.id}}(values)
        record.save || raise RecordInvalid.new(record)
        record
      end

      {% if dependent == :destroy %}
        __dependent_destroy {{name.id}}.try(&.destroy)
      {% end %}
    end
  end
end
