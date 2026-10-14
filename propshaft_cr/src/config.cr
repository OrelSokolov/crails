# Propshaft::Config — дефолты портированы из Propshaft::Railtie
# (propshaft 1.3.2 lib/propshaft/railtie.rb). output_path/manifest_path
# в геме вычисляются after_initialize как
# File.join(public, prefix) — здесь это дефолты полей.

class Propshaft::Config
  property paths : Array(String) = [] of String
  property prefix : String = "/assets"
  property version : String? = "1"
  property excluded_paths : Array(String) = [] of String
  property output_path : String = "public/assets"
  property manifest_path : String = "public/assets/.manifest.json"
  property integrity_hash_algorithm : String? = nil
  property relative_url_root : String? = nil
  property server : Bool = true
  # CRails-расширение (не в геме): прекомпрессия соседями .gz/.br при
  # процессинге (отдаёт static.cr по Accept-Encoding).
  property versions : Array(String) = [] of String

  # Регистрации компиляторов: [mime, klass], применяются по порядку.
  property compilers : Array(Tuple(String, Propshaft::Compiler.class)) = DEFAULT_COMPILERS

  DEFAULT_COMPILERS = [
    {"text/css", Propshaft::Compiler::CssAssetUrls},
    {"text/css", Propshaft::Compiler::SourceMappingUrls},
    {"text/javascript", Propshaft::Compiler::JsAssetUrls},
    {"text/javascript", Propshaft::Compiler::SourceMappingUrls},
  ] of Tuple(String, Propshaft::Compiler.class)
end
