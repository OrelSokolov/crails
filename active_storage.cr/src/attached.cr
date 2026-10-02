# Attached::One — the has_one_attached proxy (attach/attached?/detach/
# download/blob), and the macro that wires it into ActiveRecord models.

module ActiveStorage
  module Attached
    class One
      @cached_attachment : Attachment?

      def initialize(@name : String, @record : ActiveRecord::Base)
      end

      def attach(io : String, filename : String, content_type : String) : Blob
        detach if attached?
        blob = Blob.create_and_upload!(io: io, filename: filename, content_type: content_type)
        @cached_attachment = Attachment.create({
          "name"        => @name,
          "record_type" => @record.class.name.to_s,
          "record_id"   => @record.id.not_nil!,
          "blob_id"     => blob.id.not_nil!,
        })
        blob
      end

      def attached? : Bool
        find_attachment != nil
      end

      def blob : Blob?
        find_attachment.try { |a| Blob.find(a.blob_id.not_nil!) }
      end

      def download : String
        blob.not_nil!.download
      end

      def filename : String
        blob.not_nil!.filename.not_nil!
      end

      def detach : Nil
        find_attachment.try(&.destroy)
        @cached_attachment = nil
      end

      def purge : Nil
        if a = find_attachment
          Blob.find(a.blob_id.not_nil!).purge
        end
        @cached_attachment = nil
      end

      private def find_attachment : Attachment?
        @cached_attachment ||= Attachment.find_by(
          name: @name,
          record_type: @record.class.name.to_s,
          record_id: @record.id.not_nil!
        )
      end
    end
  end
end

# Wire the DSL into AR models (the gem does this via a railtie).
class ActiveRecord::Base
  macro has_one_attached(name)
    @as_attached_{{name.id}} : ActiveStorage::Attached::One?

    def {{name.id}} : ActiveStorage::Attached::One
      @as_attached_{{name.id}} ||= ActiveStorage::Attached::One.new({{name.stringify}}, self)
    end

    def {{name.id}}_blob : ActiveStorage::Blob?
      {{name.id}}.blob
    end
  end
end
