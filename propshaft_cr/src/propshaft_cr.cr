# propshaft_cr — порт propshaft 1.3.2 (компилятор asset pipeline).
#
# Oracle: oracle/propshaft_cases.rb → oracle/propshaft_expected.yml
# (44 кейса с настоящего propshaft 1.3.2), зеркало — spec/propshaft_spec.cr.
#
# Семантика 1:1 (сверено оракулом):
# - digest = SHA1(сырой контент + контенты referenced-ассетов +
#   version) первые 8 hex-символов;
# - манифест .manifest.json — компактный JSON вида
#   {"<logical>":{"digested_path":"...","integrity":null}} в порядке
#   readdir, без завершающего перевода строки;
# - digested_path вставляет -<digest> перед последним расширением;
#   файл БЕЗ расширения не получает digest вовсе;
# - JS-резолвинг — RAILS_ASSET_URL("...") (НЕ new URL(import.meta.url));
# - .mjs/.map не имеют Mime-типа в Rails 8.1.4 → pass-through копия.
#
# Задокументированные отклонения от гема:
# - прекомпрессия .gz/.br — CRails-расширение (гем не пишет соседей);
# - процесс однопоточный (parallel гема не портировался);
# - content_type-таблица — минимальная (css/js), остальное pass-through;
#   отдачу делает railties_cr static.cr со своей MIME-таблицей.

require "digest/sha1"
require "openssl"
require "base64"
require "json"
require "file_utils"
require "compress/gzip"
require "time"

module Propshaft
  class Error < Exception; end

  # Raised when the requested asset is not in the load path.
  class MissingAssetError < Error
    def initialize(@path : String)
      super()
    end

    def message : String?
      "The asset '#{@path}' was not found in the load path."
    end
  end

  # Gem logs "Writing ..." / "Unable to resolve ..." — порт пишет то же
  # в настраиваемый IO (спеки глушат его IO::NULL).
  class_property logger : IO = STDERR
end

require "./config"
require "./compiler"
require "./compiler/css_asset_urls"
require "./compiler/js_asset_urls"
require "./compiler/source_mapping_urls"
require "./compilers"
require "./asset"
require "./manifest"
require "./load_path"
require "./output_path"
require "./processor"
require "./resolver"
require "./assembly"
