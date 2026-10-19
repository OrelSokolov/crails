# Порт Propshaft::Processor (lib/propshaft/processor.rb, propshaft 1.3.2).
#
# Отклонение (CRails-расширение): versions = [".gz", ".br"] — прекомпрессия
# соседями digest-файлов; static.cr отдаёт их по Accept-Encoding. Гем ничего
# подобного не пишет. .gz — Compress::Gzip (stdlib), .br — чистый Crystal
# (шард brotli, Brotli.encode quality 11).

require "brotli"

class Propshaft::Processor
  attr_reader load_path : Propshaft::LoadPath
  attr_reader output_path : String
  attr_reader compilers : Propshaft::Compilers
  attr_reader manifest_path : String

  def initialize(@load_path : Propshaft::LoadPath, @output_path : String,
                 @compilers : Propshaft::Compilers, @manifest_path : String,
                 @versions : Array(String) = [] of String)
  end

  def process : Propshaft::Manifest
    ensure_output_path_exists
    write_manifest
    output_assets
    @load_path.manifest
  end

  def clobber : Nil
    FileUtils.rm_r(@output_path) if File.exists?(@output_path)
  end

  def clean(count : Int32 = 2, age : Time::Span = 1.hour) : Nil
    Propshaft::OutputPath.new(@output_path, @load_path.manifest).clean(count, age)
  end

  private def ensure_output_path_exists : Nil
    FileUtils.mkdir_p(@output_path)
  end

  private def write_manifest : Nil
    FileUtils.mkdir_p(File.dirname(@manifest_path))
    File.write(@manifest_path, @load_path.manifest.to_json)
  end

  private def output_assets : Nil
    @load_path.assets.each do |asset|
      dest = dest_path(asset)
      next if File.exists?(dest)
      Propshaft.logger << "Writing #{asset.digested_path}\n"
      FileUtils.mkdir_p(File.dirname(dest))
      output_asset(asset)
    end
  end

  private def output_asset(asset : Propshaft::Asset) : Nil
    if @compilers.compilable?(asset)
      File.write(dest_path(asset), asset.compiled_content)
    else
      FileUtils.cp(asset.path, dest_path(asset))
    end
    write_versions(asset)
  end

  private def dest_path(asset : Propshaft::Asset) : String
    File.join(@output_path, asset.digested_path)
  end

  # CRails-расширение: .gz/.br рядом с digest-файлом. Только текстовые
  # ассеты (content_type известен); .br — шард brotli (quality 11, как
  # `brotli -q 11` у CLI).
  private def write_versions(asset : Propshaft::Asset) : Nil
    return if @versions.empty? || asset.content_type.nil?
    data = File.read(dest_path(asset))
    @versions.each do |ext|
      case ext
      when ".gz"
        File.open("#{dest_path(asset)}.gz", "w") do |file|
          Compress::Gzip::Writer.open(file) do |writer|
            writer.write(data.to_slice)
          end
        end
      when ".br"
        write_brotli(dest_path(asset))
      end
    end
  end

  private def write_brotli(source : String) : Nil
    File.write("#{source}.br", Brotli.encode(File.read(source).to_slice))
  end
end
