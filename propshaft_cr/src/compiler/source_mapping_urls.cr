# Порт Propshaft::Compiler::SourceMappingUrls (propshaft 1.3.2).

class Propshaft::Compiler::SourceMappingUrls < Propshaft::Compiler
  SOURCE_MAPPING_PATTERN = /(\/\/|\/\*)# sourceMappingURL=(.+\.map)(\s*?\*\/)?\s*?\Z/

  def compile(asset : Propshaft::Asset, input : String) : String
    input.gsub(SOURCE_MAPPING_PATTERN) do
      # Crystal's gsub yields the matched String; groups live in $~.
      match = $~
      source_mapping_url(asset.logical_path,
        asset_path(match[2], asset.logical_path), match[1], match[3]? || "")
    end
  end

  private def asset_path(source_mapping_url : String, logical_path : String) : String
    prefix_re = /^(.+\/)?#{Regex.escape(url_prefix)}\//
    stripped = source_mapping_url.gsub(prefix_re, "")
    dir = File.dirname(logical_path)
    dir == "." ? stripped : "#{dir}/#{stripped}"
  end

  private def source_mapping_url(logical_path : String, resolved_path : String,
                                 comment_start : String, comment_end : String) : String
    if asset = @assembly.load_path.find(resolved_path)
      "#{comment_start}# sourceMappingURL=#{url_prefix}/#{asset.digested_path}#{comment_end}"
    else
      Propshaft.logger << "Removed sourceMappingURL comment for missing asset '#{resolved_path}' from #{logical_path}\n"
      "#{comment_start}#{comment_end}"
    end
  end
end
