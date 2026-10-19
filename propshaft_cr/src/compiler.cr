# Порт Propshaft::Compiler (базовый класс, lib/propshaft/compiler.rb).

abstract class Propshaft::Compiler
  attr_reader assembly : Propshaft::Assembly

  def initialize(@assembly : Propshaft::Assembly)
  end

  abstract def compile(asset : Propshaft::Asset, input : String) : String

  def referenced_by(asset : Propshaft::Asset) : Array(Propshaft::Asset)
    [] of Propshaft::Asset
  end

  private def url_prefix : String
    File.join(@assembly.config.relative_url_root.to_s,
              @assembly.config.prefix.to_s).chomp('/')
  end

  # Pathname#+ smart-конкатенация: "." + "x.png" → "x.png",
  # "deep" + "sub/x.png" → "deep/sub/x.png".
  protected def join_dir(directory : String, filename : String) : String
    directory == "." ? filename : "#{directory}/#{filename}"
  end

  # Pathname(...).relative_path_from("") — лексическая нормализация
  # ("deep/../bg2.png" → "bg2.png", ведущие ".." сохраняются).
  protected def cleanpath(path : String) : String
    parts = path.split('/')
    out = [] of String
    parts.each do |part|
      case part
      when "", "."
        # skip
      when ".."
        if out.empty? || out.last == ".."
          out << ".."
        else
          out.pop
        end
      else
        out << part
      end
    end
    out.join('/')
  end

  # Общая для Css/JsAssetUrls логика resolve_path (1:1 с гемом).
  protected def resolve_path(directory : String, filename : String) : String
    if filename.starts_with?("../")
      cleanpath("#{directory}/#{filename}")
    elsif filename.starts_with?("/")
      filename.lchop('/')
    else
      join_dir(directory, filename.lchop?("./") || filename)
    end
  end
end
