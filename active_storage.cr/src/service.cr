# Services: Disk implementation + the global service accessor.
# `ActiveStorage.service` plays the role of the Rails service registry
# for P0 (one named Disk service; S3/Mirror are P1).

require "openssl"

module ActiveStorage
  class IntegrityError < Exception; end

  module Checksum
    # Ruby: Digest::MD5.base64digest(data)
    def self.md5_base64(data : String) : String
      Base64.strict_encode(OpenSSL::Digest.new("MD5").update(data).final)
    end
  end

  class DiskService
    getter name : String

    def initialize(@root : String, @name : String = "Local")
      Dir.mkdir_p(@root)
    end

    def upload(key : String, data : String, checksum : String? = nil) : Nil
      path = path_for(key)
      Dir.mkdir_p(File.dirname(path))
      File.write(path, data)
      if checksum && Checksum.md5_base64(data) != checksum
        delete(key)
        raise IntegrityError.new("checksum mismatch for #{key}")
      end
    end

    def download(key : String) : String
      File.read(path_for(key))
    end

    def exist?(key : String) : Bool
      File.exists?(path_for(key))
    end

    def delete(key : String) : Nil
      File.delete(path_for(key))
    rescue File::NotFoundError
    end

    private def path_for(key : String) : String
      raise ArgumentError.new("unsafe key: #{key}") if key.includes?("..")
      File.join(@root, key)
    end
  end

  class_property service : DiskService = DiskService.new(File.join(Dir.tempdir, "active_storage_cr"))

  def self.service_name : String
    service.name
  end
end
