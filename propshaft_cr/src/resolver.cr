# Порты Propshaft::Resolver::Static / ::Dynamic
# (lib/propshaft/resolver/*.rb, propshaft 1.3.2). Используются вью-хелперами
# (compute_asset_path): Static — по .manifest.json (precompiled),
# Dynamic — по load path (dev).

module Propshaft::Resolver
  abstract def resolve(logical_path : String) : String?
  abstract def integrity(logical_path : String) : String?
  abstract def read(logical_path : String) : String?

  class Static
    getter manifest_path : String
    getter prefix : String

    def initialize(@manifest_path : String, @prefix : String)
    end

    def resolve(logical_path : String) : String?
      if entry = manifest[logical_path]
        File.join(@prefix, entry.digested_path)
      end
    end

    def integrity(logical_path : String) : String?
      manifest[logical_path]?.try(&.integrity)
    end

    def read(logical_path : String) : String?
      if entry = manifest[logical_path]
        File.read(File.join(File.dirname(@manifest_path), entry.digested_path))
      end
    end

    @manifest : Propshaft::Manifest?

    private def manifest : Propshaft::Manifest
      @manifest ||= Propshaft::Manifest.from_path(@manifest_path)
    end
  end

  class Dynamic
    getter load_path : Propshaft::LoadPath
    getter prefix : String

    def initialize(@load_path : Propshaft::LoadPath, @prefix : String)
    end

    def resolve(logical_path : String) : String?
      if asset = @load_path.find(logical_path)
        File.join(@prefix, asset.digested_path)
      end
    end

    def integrity(logical_path : String) : String?
      algorithm = @load_path.integrity_hash_algorithm
      if algorithm && (asset = @load_path.find(logical_path))
        asset.integrity(algorithm)
      end
    end

    def read(logical_path : String) : String?
      @load_path.find(logical_path).try(&.content)
    end
  end
end
