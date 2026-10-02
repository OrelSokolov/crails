# ActiveStorage::Blob — AR-backed blob record + upload/download/purge.
# Oracle: blob_* cases (activestorage 8.1.4): MD5-base64 checksum,
# content-type predicates, key token shape [A-Za-z0-9]{24}.

module ActiveStorage
  class Blob < ActiveRecord::Base
    set_table_name "active_storage_blobs"

    KEY_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"

    def self.generate_key : String
      String.build do |io|
        24.times { io << KEY_ALPHABET[Random::Secure.rand(KEY_ALPHABET.size)] }
      end
    end

    def self.create_and_upload!(io : String, filename : String,
                                content_type : String) : self
      key = generate_key
      checksum = Checksum.md5_base64(io)
      ActiveStorage.service.upload(key, io, checksum)
      create!({
        "key"          => key,
        "filename"     => filename,
        "content_type" => content_type,
        "metadata"     => nil,
        "service_name" => ActiveStorage.service_name,
        "byte_size"    => io.bytesize.to_i64,
        "checksum"     => checksum,
      })
    end

    def download : String
      ActiveStorage.service.download(key.not_nil!)
    end

    def purge : Nil
      Attachment.where("blob_id = ?", id.not_nil!).to_a.each(&.destroy)
      destroy
      ActiveStorage.service.delete(key.not_nil!)
    end

    def text? : Bool
      content_type.to_s.starts_with?("text/")
    end

    def image? : Bool
      content_type.to_s.starts_with?("image/")
    end

    def video? : Bool
      content_type.to_s.starts_with?("video/")
    end

    def audio? : Bool
      content_type.to_s.starts_with?("audio/")
    end
  end

  class Attachment < ActiveRecord::Base
    set_table_name "active_storage_attachments"

    def blob : Blob
      Blob.find(blob_id.not_nil!)
    end
  end
end
