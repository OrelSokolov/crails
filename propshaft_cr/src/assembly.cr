# Порт Propshaft::Assembly (lib/propshaft/assembly.rb, propshaft 1.3.2).

class Propshaft::Assembly
  attr_reader config : Propshaft::Config

  def initialize(@config : Propshaft::Config = Propshaft::Config.new)
  end

  @load_path : Propshaft::LoadPath?

  def load_path : Propshaft::LoadPath
    @load_path ||= Propshaft::LoadPath.new(
      @config.paths,
      compilers: compilers,
      version: @config.version,
      integrity_hash_algorithm: @config.integrity_hash_algorithm
    )
  end

  @resolver : Propshaft::Resolver?

  # Манифест существует → Static (precompiled), иначе Dynamic (dev).
  def resolver : Propshaft::Resolver
    @resolver ||= if File.exists?(@config.manifest_path)
      Propshaft::Resolver::Static.new(@config.manifest_path, @config.prefix)
    else
      Propshaft::Resolver::Dynamic.new(load_path, @config.prefix)
    end
  end

  def prefix : String
    @config.prefix.ends_with?('/') ? @config.prefix : "#{@config.prefix}/"
  end

  @processor : Propshaft::Processor?

  def processor : Propshaft::Processor
    @processor ||= Propshaft::Processor.new(
      load_path: load_path,
      output_path: @config.output_path,
      compilers: compilers,
      manifest_path: @config.manifest_path,
      versions: @config.versions
    )
  end

  @compilers : Propshaft::Compilers?

  def compilers : Propshaft::Compilers
    @compilers ||= Propshaft::Compilers.new(self).tap do |compilers|
      @config.compilers.each { |mime, klass| compilers.register(mime, klass) }
    end
  end

  def reveal(path_type : Symbol = :logical_path) : Array(String)
    load_path.assets.map do |asset|
      path_type == :path ? asset.path : asset.logical_path
    end
  end
end
