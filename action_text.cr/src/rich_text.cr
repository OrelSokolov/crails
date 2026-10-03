# RichText: the action_text_rich_texts row. Held behind has_rich_text.
#
# Deliberate P0 deviation: this is a hand-rolled row class over
# ActiveRecord::Base.connection rather than a full ActiveRecord model —
# the AR codegen would override #to_s/#body with attribute accessors
# (later defs win in Crystal). RichText#body is the raw HTML string,
# exactly what Rails serializes into the body column.

module ActionText
  class RichText
    TABLE = "action_text_rich_texts"

    property id : Int64?
    property name : String?
    property body : String?
    property record_type : String?
    property record_id : Int64?
    property? new_record = true

    def initialize(@name : String? = nil, @body : String? = nil,
                   @record_type : String? = nil, @record_id : Int64? = nil)
    end

    def self.create(attrs : Hash) : RichText
      record = RichText.new(
        name: attrs["name"]?.try(&.to_s),
        body: attrs["body"]?.try(&.to_s),
        record_type: attrs["record_type"]?.try(&.to_s),
        record_id: attrs["record_id"]?.as?(Int64)
      )
      record.save
      record
    end

    def self.find_by(**conditions) : RichText?
      where(conditions.to_h).first?
    end

    def self.where(**conditions) : Array(RichText)
      where(conditions.to_h)
    end

    def self.where(conditions : Hash) : Array(RichText)
      clauses = [] of String
      args = [] of ActiveRecord::Value
      conditions.each do |key, value|
        clauses << "#{key} = $#{clauses.size + 1}"
        args << value.as(ActiveRecord::Value)
      end
      sql = "SELECT id, name, body, record_type, record_id FROM #{TABLE}"
      sql += " WHERE #{clauses.join(" AND ")}" unless clauses.empty?
      sql += " ORDER BY id"
      rows = [] of RichText
      ActiveRecord::Base.connection.query(sql, args: args) do |rs|
        rs.each do
          rows << from_row(rs)
        end
      end
      rows
    end

    def self.count(**conditions) : Int64
      where(conditions.to_h).size.to_i64
    end

    def self.from_row(rs : DB::ResultSet) : RichText
      record = RichText.new
      record.id = rs.read(Int64?)
      record.name = rs.read(String?)
      record.body = rs.read(String?)
      record.record_type = rs.read(String?)
      record.record_id = rs.read(Int64?)
      record.new_record = false
      record
    end

    def save : Nil
      now = Time.utc
      if (existing_id = id) && !new_record?
        ActiveRecord::Base.connection.exec(
          "UPDATE #{TABLE} SET name = $1, body = $2, record_type = $3, record_id = $4, updated_at = $5 WHERE id = $6",
          args: [name, body, record_type, record_id, now, existing_id]
        )
      else
        @id = ActiveRecord::Base.connection.scalar(
          "INSERT INTO #{TABLE} (name, body, record_type, record_id, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id",
          args: [name, body, record_type, record_id, now, now]
        ).as(Int64)
        @new_record = false
      end
    end

    # --- ActionText API --------------------------------------------------

    def to_body_content : Content
      Content.new(body.to_s)
    end

    def to_plain_text : String
      to_body_content.to_plain_text
    end

    # The gem delegates to_s to the Content (layout-wrapped sanitized HTML).
    def to_s : String
      to_body_content.to_s
    end

    def present? : Bool
      !to_plain_text.empty?
    end

    def blank? : Bool
      !present?
    end

    def inspect(io : IO) : Nil
      io << "#<ActionText::RichText name=" << name.inspect << ", body=" << body.inspect << ">"
    end
  end
end

# Wire the DSL into AR models (the gem does this via the engine railtie:
# ActiveRecord::Base.include ActionText::Attribute).
class ActiveRecord::Base
  macro has_rich_text(name)
    @at_rich_text_{{name.id}} : ::ActionText::RichText?

    def {{name.id}} : ::ActionText::RichText
      if rt = @at_rich_text_{{name.id}}
        rt
      elsif (record_id = self.id) &&
            (rt = ::ActionText::RichText.find_by(
              record_type: self.class.name.to_s, record_id: record_id, name: {{name.id.stringify}}
            ))
        @at_rich_text_{{name.id}} = rt
      else
        rt = ::ActionText::RichText.new(name: {{name.id.stringify}}, record_type: self.class.name.to_s)
        @at_rich_text_{{name.id}} = rt
        rt
      end
    end

    def {{name.id}}? : Bool
      rt = @at_rich_text_{{name.id}} ||
           (self.id.try do |record_id|
             ::ActionText::RichText.find_by(
               record_type: self.class.name.to_s, record_id: record_id, name: {{name.id.stringify}}
             )
           end)
      rt ? rt.present? : false
    end

    def {{name.id}}=(body : String) : String
      rt = {{name.id}}
      rt.body = body
      @at_rich_text_{{name.id}} = rt
      body
    end

    # Rails autosaves the dependent RichText row with the owner; the AR
    # callback runners pick these up via the after_create__cb_ prefix.
    def after_create__cb_at_rich_text_{{name.id}} : Nil
      __at_persist_rich_text_{{name.id}}(true)
    end

    def after_update__cb_at_rich_text_{{name.id}} : Nil
      __at_persist_rich_text_{{name.id}}(false)
    end

    def __at_persist_rich_text_{{name.id}}(creating : Bool) : Nil
      if rt = @at_rich_text_{{name.id}}
        rt.name = {{name.id.stringify}}
        rt.record_type = self.class.name.to_s
        rt.record_id = self.id
        rt.save
      end
      nil
    end

    # Message.create!(content: "<h1>...</h1>") — pull the rich text key
    # out of the attribute hash before the AR create! runs.
    def self.create!(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : self
      vals = values.dup
      rt_body = vals.delete({{name.id.stringify}}).try(&.to_s)
      record = super(vals)
      if rt_body
        record.{{name.id}} = rt_body
        record.save
      end
      record
    end

    def self.create(values : Hash(String, ::ActiveRecord::Value) = {} of String => ::ActiveRecord::Value) : self
      vals = values.dup
      rt_body = vals.delete({{name.id.stringify}}).try(&.to_s)
      record = super(vals)
      if rt_body
        record.{{name.id}} = rt_body
        record.save
      end
      record
    end
  end
end
