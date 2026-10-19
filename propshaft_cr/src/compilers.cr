# Порт Propshaft::Compilers (lib/propshaft/compilers.rb, propshaft 1.3.2).

class Propshaft::Compilers
  attr_reader registrations : Hash(String, Array(Propshaft::Compiler.class))

  def initialize(@assembly : Propshaft::Assembly)
    @registrations = {} of String => Array(Propshaft::Compiler.class)
  end

  def register(mime_type : String, klass : Propshaft::Compiler.class) : Nil
    (@registrations[mime_type] ||= [] of Propshaft::Compiler.class) << klass
  end

  def any? : Bool
    !registrations.empty?
  end

  def compilable?(asset : Propshaft::Asset) : Bool
    registrations.has_key?(asset.content_type.to_s)
  end

  def compile(asset : Propshaft::Asset) : String
    if relevant = registrations[asset.content_type.to_s]?
      input = asset.content
      relevant.each { |compiler| input = compiler.new(@assembly).compile(asset, input) }
      input
    else
      asset.content
    end
  end

  def referenced_by(asset : Propshaft::Asset) : Array(Propshaft::Asset)
    references = [] of Propshaft::Asset
    if relevant = registrations[asset.content_type.to_s]?
      relevant.each do |compiler|
        compiler.new(@assembly).referenced_by(asset).each do |a|
          references << a unless references.any? { |x| x.logical_path == a.logical_path }
        end
      end
    end
    references
  end
end
