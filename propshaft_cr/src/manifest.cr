# Порт Propshaft::Manifest (lib/propshaft/manifest.rb, propshaft 1.3.2).
# Формат сериализации: компактный JSON, значения —
# {"digested_path":"...","integrity":null}; при чтении поддержан
# старый "простой" формат (значение-строка).

class Propshaft::Manifest
  class Entry
    getter logical_path : String
    getter digested_path : String
    getter integrity : String?

    def initialize(@logical_path : String, @digested_path : String,
                   @integrity : String?)
    end
  end

  getter integrity_hash_algorithm : String?

  def initialize(@integrity_hash_algorithm : String? = nil)
    @entries = {} of String => Entry
  end

  def self.from_path(manifest_path : String) : self
    manifest = Manifest.new
    JSON.parse(File.read(manifest_path)).as_h.each do |key, value|
      digested_path, integrity =
        if (simple = value.as_s?)
          {simple, nil}
        else
          obj = value.as_h
          {obj["digested_path"].as_s,
           obj["integrity"]?.try(&.as_s?)}
        end
      manifest.push(Entry.new(key, digested_path, integrity))
    end
    manifest
  end

  def push_asset(asset : Propshaft::Asset) : Entry
    algorithm = @integrity_hash_algorithm
    entry = Entry.new(asset.logical_path, asset.digested_path,
      algorithm ? asset.integrity(algorithm) : nil)
    push(entry)
  end

  def push(entry : Entry) : Entry
    @entries[entry.logical_path] = entry
    entry
  end

  def [](logical_path : String) : Entry?
    @entries[logical_path]?
  end

  def delete(logical_path : String) : Entry?
    @entries.delete(logical_path)
  end

  # Побайтово как to_json гема: порядок вставки, компактно, без \n в конце.
  def to_json : String
    String.build do |io|
      JSON.build(io) do |json|
        json.object do
          @entries.each do |logical, entry|
            json.field logical do
              json.object do
                json.field "digested_path", entry.digested_path
                json.field "integrity", entry.integrity
              end
            end
          end
        end
      end
    end
  end
end
