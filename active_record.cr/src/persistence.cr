# Persistence: save/create/update/destroy + dirty tracking.
# Oracle-verified against activerecord 8.1.4 (oracle/expected.yml).

module ActiveRecord
  class Base
    # --- dirty -----------------------------------------------------------

    def attribute_changed?(name : String, value : Value) : Bool
      if __original_attributes.has_key?(name)
        __original_attributes[name] != value
      else
        value != default_for(name)
      end
    end

    def changed_attribute?(name : String) : Bool
      __original_attributes.has_key?(name) && __original_attributes[name] != attributes[name]
    end

    def default_for(name : String) : Value
      defaults = self.class.__column_defaults
      defaults.has_key?(name) ? defaults[name] : nil
    end

    def changed? : Bool
      attributes.any? { |name, value| attribute_changed?(name, value) }
    end

    def changed : Array(String)
      attributes.select { |name, value| attribute_changed?(name, value) }.keys
    end

    def changes : Hash(String, Tuple(Value, Value))
      result = {} of String => Tuple(Value, Value)
      attributes.each do |name, value|
        if attribute_changed?(name, value)
          from = __original_attributes.has_key?(name) ? __original_attributes[name] : default_for(name)
          result[name] = {from.as(Value), value}
        end
      end
      result
    end

    # --- save / create ----------------------------------------------------

    def save(validate : Bool = true) : Bool
      return false if destroyed?
      return false unless validate ? valid? : true
      return false unless __run_before_save
      tx_event : Symbol = new_record? ? :create : :update
      tx = Base.__current_tx
      Base.__register_in_transaction(self, tx_event)
      begin
        __persist_changes
        __run_after_commit(tx_event) unless tx
        true
      rescue ex : DB::Error | PQ::PQError
        __run_after_rollback(tx_event) unless tx
        raise RecordNotUnique.new(ex.message) if ex.message.try(&.includes?("duplicate key"))
        raise ex
      end
    end

    private def __persist_changes : Nil
      changes_to_write = changes
      if new_record?
        __write_timestamps_on_create
        id = __insert(changes_to_write.keys + (changes_to_write.keys & ["created_at", "updated_at"]))
        @id = id
        self.new_record = false
        __run_after_create
      else
        changes_to_write = __merge_updated_at_change(changes_to_write)
        __update(changes_to_write) unless changes_to_write.empty?
        __run_after_update
      end
      __run_after_save
      @previous_changes = changes_to_write
      __snapshot_original!
    end

    def save! : Bool
      save || raise RecordInvalid.new(self)
    end

    def self.create(values : Hash(String, Value) = {} of String => Value) : self
      record = new
      record.assign_attributes(values)
      record.save
      record
    end

    def self.create!(values : Hash(String, Value) = {} of String => Value) : self
      record = new
      record.assign_attributes(values)
      record.save || raise RecordInvalid.new(record)
      record
    end

    def update(values : Hash(String, Value)) : Bool
      assign_attributes(values)
      save
    end

    def update!(values : Hash(String, Value)) : Bool
      assign_attributes(values)
      save || raise RecordInvalid.new(self)
    end

    def update_attributes(values : Hash(String, Value)) : Bool
      update(values)
    end

    def self.update(id : Int64 | Int32, values : Hash(String, Value)) : self
      record = find(id)
      record.update(values) || raise ActiveRecordError.new("Failed to update #{self} #{id}")
      record
    end

    def self.update!(id : Int64 | Int32, values : Hash(String, Value)) : self
      record = find(id)
      record.update!(values)
      record
    end

    def self.destroy(id : Int64 | Int32) : self
      find(id).destroy
    end

    def self.delete(id : Int64 | Int32) : Int64
      Base.__session.exec(
        "DELETE FROM #{quoted_table_name} WHERE \"id\" = $1", args: [id.to_i64]).rows_affected
    end

    # --- destroy ----------------------------------------------------------

    def destroy : self
      unless destroyed?
        __run_before_destroy
        tx = Base.__current_tx
        if (pk = @id)
          Base.__register_in_transaction(self, :destroy)
          __run_dependents
          Base.__session.exec(
            "DELETE FROM #{self.class.quoted_table_name} WHERE \"id\" = $1", args: [pk])
        end
        self.destroyed = true
        self.new_record = false
        __run_after_destroy
        __run_after_commit(:destroy) unless tx
      end
      self
    end

    # No real freeze in Crystal: `frozen?` mirrors post-destroy state.
    def frozen? : Bool
      destroyed?
    end

    # --- low-level ----------------------------------------------------------

    def update_columns(values : Hash(String, Value)) : Nil
      raise ActiveRecordError.new("can't update_columns a new record") if new_record?
      pk = @id.not_nil!
      assign_attributes(values)
      sets = values.keys.map { |k| %("#{k.gsub('"', "")}") }
      args = [] of DB::Any
      values.each_value { |v| args << v.as(DB::Any) }
      sql = "UPDATE #{self.class.quoted_table_name} SET #{sets.map_with_index { |s, i| "#{s} = $#{i + 1}" }.join(", ")} WHERE \"id\" = $#{values.size + 1}"
      args << pk
      Base.__session.exec(sql, args: args)
      __snapshot_original!
    end

    def touch : self
      touch("updated_at")
    end

    def touch(*columns : String) : self
      raise ActiveRecordError.new("can't touch a new record") if new_record?
      now = Time.utc
      cols = columns.empty? ? ["updated_at"] : columns.to_a
      assignments = cols.map { |c| %("#{c.gsub('"', "")}") }
      args = [] of DB::Any
      cols.each { |_c| args << now.as(DB::Any) }
      pk = @id.not_nil!
      sql = "UPDATE #{self.class.quoted_table_name} SET #{assignments.map_with_index { |s, i| "#{s} = $#{i + 1}" }.join(", ")} WHERE \"id\" = $#{cols.size + 1}"
      args << pk
      Base.__session.exec(sql, args: args)
      cols.each { |c| assign_attributes({c => now}) }
      __snapshot_original!
      self
    end

    # --- bulk -----------------------------------------------------------

    def self.insert_all!(rows : Array(Hash(String, Value))) : Int64
      insert_all(rows, "") # "" → no conflict clause → raises on duplicates
    end

    def self.insert_all(rows : Array(Hash(String, Value)), conflict_clause : String = "DO NOTHING") : Int64
      return 0_i64 if rows.empty?
      # Rails fills created_at/updated_at on bulk inserts (touch semantics).
      if __column_names.includes?("created_at")
        now = Time.utc
        rows = rows.map do |row|
          dup = row.dup
          dup["created_at"] = now unless dup["created_at"]?
          dup["updated_at"] = now unless dup["updated_at"]?
          dup
        end
      end
      cols = rows.first.keys
      col_sql = cols.map { |c| %("#{c.gsub('"', "")}") }.join(", ")
      values_sql = [] of String
      args = [] of DB::Any
      rows.each do |row|
        placeholders = cols.map do |c|
          args << (row[c]?.as(DB::Any))
          "$#{args.size}"
        end
        values_sql << "(#{placeholders.join(", ")})"
      end
      tail = conflict_clause.empty? ? "" : " ON CONFLICT #{conflict_clause}"
      sql = "INSERT INTO #{quoted_table_name} (#{col_sql}) VALUES #{values_sql.join(", ")}#{tail}"
      Base.__session.exec(sql, args: args).rows_affected
    end

    def self.upsert_all(rows : Array(Hash(String, Value))) : Int64
      insert_all(rows, "DO NOTHING")
    end

    def self.quoted_table_name : String
      %("#{table_name.gsub('"', "")}")
    end

    # --- find_or_create ------------------------------------------------

    def self.find_or_create_by(where : Hash(String, Value), extra : Hash(String, Value) = {} of String => Value) : self
      found = where_clause_relation(where).first
      return found if found
      record = new
      record.assign_attributes(where.merge(extra))
      record.save
      record
    end

    def self.find_or_create_by!(where : Hash(String, Value), extra : Hash(String, Value) = {} of String => Value) : self
      found = where_clause_relation(where).first
      return found if found
      record = new
      record.assign_attributes(where.merge(extra))
      record.save || raise RecordInvalid.new(record)
      record
    end

    def self.where_clause_relation(where : Hash(String, Value))
      rel = all
      where.each do |k, v|
        rel = rel.where(%("#{k.gsub('"', "")}" = ?), v.as(DB::Any))
      end
      rel
    end

    # --- internals --------------------------------------------------------

    def __insert(cols : Array(String)) : Int64
      attrs = attributes
      col_names = cols.empty? ? (self.class.__column_names - ["id"]) : cols.select { |c| c != "id" }
      col_names = (col_names + ["created_at", "updated_at"]).uniq
      args = [] of DB::Any
      placeholders = col_names.map do |c|
        args << attrs[c]?.as(DB::Any)
        "$#{args.size}"
      end
      col_sql = col_names.map { |c| %("#{c.gsub('"', "")}") }.join(", ")
      sql = "INSERT INTO #{self.class.quoted_table_name} (#{col_sql}) VALUES (#{placeholders.join(", ")}) RETURNING \"id\""
      Base.__session.query_one(sql, args: args, as: Int64)
    end

    def __update(changes : Hash(String, Tuple(Value, Value))) : Nil
      pk = @id.not_nil!
      col_names = changes.keys
      args = [] of DB::Any
      sets = col_names.map_with_index do |c, i|
        args << changes[c][1].as(DB::Any)
        %("#{c.gsub('"', "")}") + " = $#{i + 1}"
      end
      args << pk
      sql = "UPDATE #{self.class.quoted_table_name} SET #{sets.join(", ")} WHERE \"id\" = $#{col_names.size + 1}"
      Base.__session.exec(sql, args: args)
    end

    def __write_timestamps_on_create : Nil
      now = Time.utc
      assign_attributes({"created_at" => now}) if self.class.__column_names.includes?("created_at") && attributes["created_at"]?.nil?
      assign_attributes({"updated_at" => now}) if self.class.__column_names.includes?("updated_at") && attributes["updated_at"]?.nil?
    end

    def __merge_updated_at_change(changes : Hash(String, Tuple(Value, Value))) : Hash(String, Tuple(Value, Value))
      if self.class.__column_names.includes?("updated_at")
        now = Time.utc
        merged = changes.dup
        merged["updated_at"] = {attributes["updated_at"]?.as(Value), now}
        assign_attributes({"updated_at" => now})
        merged
      else
        changes
      end
    end
  end

  class ActiveRecordError < Exception
  end

  class Errors
    struct Error
      getter attribute : String
      getter type : Symbol
      getter message : String?

      def initialize(@attribute, @type, @message = nil)
      end
    end

    @errors = [] of Error

    def add(attribute : String, message : String, type : Symbol = :invalid) : Nil
      @errors << Error.new(attribute, type, message)
    end

    def add(attribute : String, type : Symbol) : Nil
      @errors << Error.new(attribute, type, default_message(type))
    end

    def clear : Nil
      @errors.clear
    end

    def empty? : Bool
      @errors.empty?
    end

    def size : Int32
      @errors.size
    end

    def where(attribute : String) : Array(Error)
      @errors.select { |e| e.attribute == attribute }
    end

    def full_messages : Array(String)
      @errors.map { |e| "#{human_attribute(e.attribute)} #{e.message || default_message(e.type)}" }
    end

    private def human_attribute(name : String) : String
      name.tr("_", "").capitalize
    end

    private def default_message(type : Symbol) : String
      case type
      when :blank           then "can't be blank"
      when :too_long        then "is too long"
      when :not_a_number    then "is not a number"
      when :greater_than    then "must be greater than %{count}"
      when :less_than       then "must be less than %{count}"
      when :invalid         then "is invalid"
      when :taken           then "has already been taken"
      when :record_invalid  then "is invalid"
      else                       "is invalid"
      end
    end
  end
end
