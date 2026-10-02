# Relation(T): immutable query chain, 1:1 feel to ActiveRecord::Relation.
# WHERE fragments use `?` placeholders, converted to $n in to_sql.

module ActiveRecord
  struct Relation(T)
    include Enumerable(T)

    getter model : T.class

    @wheres = [] of String
    @args = [] of DB::Any
    @orders = [] of String
    @limit_value : Int64? = nil
    @offset_value : Int64? = nil

    def initialize(@model : T.class)
    end

    protected def initialize(@model : T.class, @wheres : Array(String),
                             @args : Array(DB::Any), @orders : Array(String),
                             @limit_value : Int64?, @offset_value : Int64?)
    end

    private def copy : Relation(T)
      Relation(T).new(@model, @wheres.dup, @args.dup, @orders.dup,
        @limit_value, @offset_value)
    end

    private def quote(col : String) : String
      %("#{col.gsub('"', "")}")
    end

    private def select_list : String
      model.__column_names.map { |c| %("#{c.gsub('"', "")}") }.join(", ")
    end

    # --- chainable ---

    def where(condition : String, *args) : Relation(T)
      r = copy
      r.@wheres << "(" + condition + ")"
      args.each { |a| r.@args << a.as(DB::Any) }
      r
    end

    def where(**opts) : Relation(T)
      r = copy
      opts.each do |key, value|
        col = quote(key.to_s)
        case value
        when Nil
          r.@wheres << "#{col} IS NULL"
        when Range
          r.@wheres << "#{col} BETWEEN ? AND ?"
          r.@args << value.begin.as(DB::Any) << value.end.as(DB::Any)
        when Array
          return r if value.empty?
          r.@wheres << "#{col} IN (#{value.map { "?" }.join(", ")})"
          value.each { |v| r.@args << v.as(DB::Any) }
        else
          r.@wheres << "#{col} = ?"
          r.@args << value.as(DB::Any)
        end
      end
      r
    end

    def not(**opts) : Relation(T)
      r = copy
      opts.each do |key, value|
        col = quote(key.to_s)
        case value
        when Nil
          r.@wheres << "#{col} IS NOT NULL"
        when Range
          r.@wheres << "#{col} NOT BETWEEN ? AND ?"
          r.@args << value.begin.as(DB::Any) << value.end.as(DB::Any)
        when Array
          if value.empty?
            r.@wheres << "1=1"
          else
            r.@wheres << "#{col} NOT IN (#{value.map { "?" }.join(", ")})"
            value.each { |v| r.@args << v.as(DB::Any) }
          end
        else
          r.@wheres << "#{col} != ?"
          r.@args << value.as(DB::Any)
        end
      end
      r
    end

    def order(*cols : String | Symbol) : Relation(T)
      r = copy
      cols.each { |c| r.@orders << order_term(c.to_s, nil) }
      r
    end

    def order(**opts) : Relation(T)
      r = copy
      opts.each { |col, dir| r.@orders << order_term(col.to_s, dir) }
      r
    end

    private def order_term(col : String, dir) : String
      parts = col.split(/\s+/)
      base = quote(parts[0])
      suffix = if parts.size > 1
                 " " + parts[1..].join(" ").upcase
               elsif dir
                 case dir.to_s.downcase
                 when "desc" then " DESC"
                 when "asc"  then " ASC"
                 else " " + dir.to_s.upcase
                 end
               else
                 ""
               end
      base + suffix
    end

    def limit(n : Int) : Relation(T)
      Relation(T).new(@model, @wheres.dup, @args.dup, @orders.dup,
        n.to_i64, @offset_value)
    end

    def offset(n : Int) : Relation(T)
      Relation(T).new(@model, @wheres.dup, @args.dup, @orders.dup,
        @limit_value, n.to_i64)
    end

    def reverse_order : Relation(T)
      orders = @orders.empty? ? [%("id" DESC)] : @orders.map do |o|
        if o =~ / DESC\z/
          o.sub(/ DESC\z/, " ASC")
        elsif o =~ / ASC\z/
          o.sub(/ ASC\z/, " DESC")
        else
          o + " DESC"
        end
      end
      Relation(T).new(@model, @wheres.dup, @args.dup, orders,
        @limit_value, @offset_value)
    end

    # --- SQL building ---

    private def build_sql(cols : String, orders : Array(String),
                          limit_override : Int64? = nil) : Tuple(String, Array(DB::Any))
      counter = 0
      where_sql = @wheres.map { |w| w.gsub(/\?/) { counter += 1; "$#{counter}" } }.join(" AND ")
      lim = limit_override || @limit_value
      sql = String.build do |io|
        io << "SELECT " << cols << " FROM " << %("#{model.table_name.gsub('"', "")}")
        io << " WHERE " << where_sql unless where_sql.empty?
        io << " ORDER BY " << orders.join(", ") unless orders.empty?
        io << " LIMIT " << lim if lim
        io << " OFFSET " << @offset_value if @offset_value
      end
      {sql, @args}
    end

    def to_sql : String
      build_sql(select_list, @orders.empty? ? [%("id" ASC)] : @orders).first
    end

    # --- materialization ---

    def each(& : T ->) : Nil
      sql, args = build_sql(select_list, @orders.empty? ? [] of String : @orders)
      Base.connection.query(sql, args: args) do |rs|
        rs.each { yield T.__from_row(rs) }
      end
    end

    def empty? : Bool
      !exists?
    end

    def exists? : Bool
      sql, args = build_sql("1", [] of String, limit_override: 1_i64)
      Base.connection.query_one?(sql, args: args, as: Int32) ? true : false
    end

    def count : Int64
      sql, args = build_sql("count(*)", [] of String)
      Base.connection.query_one(sql, args: args, as: Int64)
    end

    def size : Int64
      count
    end

    def pluck(col : String | Symbol) : Array(ActiveRecord::Value)
      sql, args = build_sql(quote(col.to_s), @orders.empty? ? [] of String : @orders)
      values = [] of ActiveRecord::Value
      Base.connection.query(sql, args: args) do |rs|
        rs.each { values << rs.read(ActiveRecord::Value) }
      end
      values
    end

    def pick(col : String | Symbol) : ActiveRecord::Value
      limit(1).pluck(col).first?
    end

    def ids : Array(Int64)
      pluck("id").map { |v| v.as(Int64) }
    end

    def take : T?
      limit(1).to_a.first?
    end

    def first : T?
      r = @orders.empty? ? order(:id) : self
      r.limit(1).to_a.first?
    end

    def first! : T
      first || raise ActiveRecord::RecordNotFound.new(
        "Couldn't find #{model} (first)")
    end

    def last : T?
      r = @orders.empty? ? order(:id) : self
      r.reverse_order.limit(1).to_a.first?
    end

    def sole : T
      records = limit(2).to_a
      case records.size
      when 1 then records.first
      when 0 then raise ActiveRecord::RecordNotFound.new("Couldn't find #{model} (sole)")
      else        raise ActiveRecord::RecordNotFound.new("Multiple #{model} found")
      end
    end

    def find_each(batch_size : Int32 = 1000, & : T ->) : Nil
      last_id = 0_i64
      loop do
        batch = where(%q("id" > ?), last_id)
          .order(:id)
          .limit(batch_size)
          .to_a
        break if batch.empty?
        batch.each do |record|
          yield record
          last_id = record.id.not_nil!
        end
        break if batch.size < batch_size
      end
    end
  end
end
