# Порт Propshaft::Compiler::CssAssetUrls (propshaft 1.3.2).

class Propshaft::Compiler::CssAssetUrls < Propshaft::Compiler
  ASSET_URL_PATTERN = /url\(\s*["']?(?!(?:\#|%23|data:|http:|https:|\/\/))([^"'\s?#)]+)([#?][^"')]+)?\s*["']?\)/

  def compile(asset : Propshaft::Asset, input : String) : String
    input.gsub(ASSET_URL_PATTERN) do
      # Crystal's gsub yields the matched String; groups live in $~.
      match = $~
      asset_url(resolve_path(File.dirname(asset.logical_path), match[1]),
        asset.logical_path, match[2]?, match[1])
    end
  end

  def referenced_by(asset : Propshaft::Asset) : Array(Propshaft::Asset)
    references = [] of Propshaft::Asset
    collect_references(asset, references)
    references
  end

  private def collect_references(asset : Propshaft::Asset,
                                 references : Array(Propshaft::Asset)) : Nil
    # Бинарные ассеты сканируются лосс-фри (Asset#scannable_content).
    asset.scannable_content.scan(ASSET_URL_PATTERN) do |m|
      referenced_asset = @assembly.load_path.find(
        resolve_path(File.dirname(asset.logical_path), m[1].not_nil!))
      if referenced_asset &&
         !references.any? { |a| a.logical_path == referenced_asset.logical_path }
        references << referenced_asset
        collect_references(referenced_asset, references)
      end
    end
  end

  private def asset_url(resolved_path : String, logical_path : String,
                        fingerprint : String?, pattern : String) : String
    if asset = @assembly.load_path.find(resolved_path)
      %(url("#{url_prefix}/#{asset.digested_path}#{fingerprint}"))
    else
      Propshaft.logger << "Unable to resolve '#{pattern}' for missing asset '#{resolved_path}' in #{logical_path}\n"
      %(url("#{pattern}"))
    end
  end
end
