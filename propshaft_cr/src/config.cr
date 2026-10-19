# Propshaft::Config — дефолты портированы из Propshaft::Railtie
# (propshaft 1.3.2 lib/propshaft/railtie.rb). output_path/manifest_path
# в геме вычисляются after_initialize как
# File.join(public, prefix) — здесь это дефолты полей.

class Propshaft::Config
  attr_accessor paths : Array(String) = [] of String
  attr_accessor prefix : String = "/assets"
  attr_accessor version : String? = "1"
  attr_accessor excluded_paths : Array(String) = [] of String
  attr_accessor output_path : String = "public/assets"
  attr_accessor manifest_path : String = "public/assets/.manifest.json"
  attr_accessor integrity_hash_algorithm : String? = nil
  attr_accessor relative_url_root : String? = nil
  attr_accessor server : Bool = true
  # CRails-расширение (не в геме): прекомпрессия соседями .gz/.br при
  # процессинге (отдаёт static.cr по Accept-Encoding).
  attr_accessor versions : Array(String) = [] of String

  # Регистрации компиляторов: [mime, klass], применяются по порядку.
  attr_accessor compilers : Array(Tuple(String, Propshaft::Compiler.class)) = DEFAULT_COMPILERS

  DEFAULT_COMPILERS = [
    {"text/css", Propshaft::Compiler::CssAssetUrls},
    {"text/css", Propshaft::Compiler::SourceMappingUrls},
    {"text/javascript", Propshaft::Compiler::JsAssetUrls},
    {"text/javascript", Propshaft::Compiler::SourceMappingUrls},
  ] of Tuple(String, Propshaft::Compiler.class)
end
