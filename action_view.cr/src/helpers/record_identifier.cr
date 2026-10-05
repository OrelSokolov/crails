# ActionView::RecordIdentifier — dom_id(record, prefix), 1:1 с
# actionview 8.1.4: `dom_id(post)` => "post_5", `dom_id(post, :new)` =>
# "new_post", новой записи => "new_post". Duck-typed: годится любой
# объект с `id : Int64?` (все AR-модели).

module ActionView
  module Helpers
    module RecordIdentifier
      def dom_id(record, prefix : String | Symbol | Nil = nil) : String
        RecordIdentifier.dom_id(record, prefix)
      end

      def self.dom_id(record, prefix : String | Symbol | Nil = nil) : String
        singular = record.class.name.underscore
        if (record_id = record.id)
          "#{dom_prefix(prefix)}#{singular}_#{record_id}"
        else
          "#{dom_prefix(prefix || "new")}#{singular}"
        end
      end

      private def self.dom_prefix(prefix : String | Symbol | Nil) : String
        prefix ? "#{prefix}_" : ""
      end
    end
  end
end
