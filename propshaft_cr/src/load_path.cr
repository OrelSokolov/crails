# Порт Propshaft::LoadPath (lib/propshaft/load_path.rb, propshaft 1.3.2).
# Порядок обхода — readdir (без сортировки), как Pathname#children в ruby;
# от этого порядка зависит порядок ключей в манифесте (пин оракулом).

class Propshaft::LoadPath
  getter paths : Array(String)
  getter compilers : Propshaft::Compilers
  getter version : String?
  getter integrity_hash_algorithm : String?

  def initialize(paths : Enumerable(String), @compilers : Propshaft::Compilers,
                 @version : String? = nil, @integrity_hash_algorithm : String? = nil)
    @paths = dedup(paths.map(&.to_s.rstrip('/')))
  end

  def find(asset_name : String) : Propshaft::Asset?
    assets_by_path[asset_name]?
  end

  def assets : Array(Propshaft::Asset)
    assets_by_path.values
  end

  # Set referenced-ассетов минус сам asset (гем: references.delete(self)).
  def find_referenced_by(asset : Propshaft::Asset) : Array(Propshaft::Asset)
    @compilers.referenced_by(asset).reject { |a| a.logical_path == asset.logical_path }
  end

  def manifest : Propshaft::Manifest
    manifest = Propshaft::Manifest.new(@integrity_hash_algorithm)
    assets.each { |asset| manifest.push_asset(asset) }
    manifest
  end

  @assets_by_path : Hash(String, Propshaft::Asset)? = nil

  private def assets_by_path : Hash(String, Propshaft::Asset)
    if cached = @assets_by_path
      return cached
    end
    mapped = {} of String => Propshaft::Asset
    @paths.each do |path|
      next unless Dir.exists?(path)
      all_files_from_tree(path).each do |file|
        next if File.basename(file).starts_with?('.')
        logical = file[(path.size + 1)..]
        mapped[logical] ||= Propshaft::Asset.new(file, logical, self)
      end
    end
    @assets_by_path = mapped
    mapped
  end

  private def all_files_from_tree(path : String) : Array(String)
    files = [] of String
    Dir.children(path).each do |child|
      full = File.join(path, child)
      if Dir.exists?(full)
        files.concat(all_files_from_tree(full))
      else
        files << full
      end
    end
    files
  end

  # dedup(paths): сортируем, выкидываем пути, начинающиеся с предыдущего
  # оставленного; порядок результата — как во входном списке (paths & deduped).
  private def dedup(paths : Array(String)) : Array(String)
    deduped = [] of String
    paths.sort.each do |path|
      deduped << path if deduped.empty? || !path.starts_with?(deduped.last)
    end
    paths & deduped
  end
end
