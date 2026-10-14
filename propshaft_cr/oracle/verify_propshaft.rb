# Reverse check: настоящий propshaft 1.3.2 проверяет выход порта.
#
#   ruby oracle/verify_propshaft.rb FIXTURE_ROOT PORT_OUTPUT_DIR
#
# Гем собирает ту же фикстуру в temp-каталог и сравнивает деревья
# побайтово (.manifest.json + все digest-файлы). Отличия — в stderr,
# ненулевой код возврата при любом расхождении.

gem "propshaft", "= 1.3.2"
gem "actionpack", "= 8.1.4"

require "rubygems"
require "ostruct"
require "fileutils"
require "tmpdir"
require "json"
require "pathname"

gem_dir = Gem::Specification.find_by_name("propshaft", "= 1.3.2").gem_dir
$LOAD_PATH.unshift(File.join(gem_dir, "lib"))
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/starts_ends_with"
require "active_support/core_ext/string/access"
require "active_support/core_ext/enumerable"
require "propshaft"

Propshaft.logger = Logger.new(File::NULL)

fixture_root, port_output = ARGV[0], ARGV[1]
abort "usage: verify_propshaft.rb FIXTURE_ROOT PORT_OUTPUT_DIR" unless fixture_root && port_output

LOAD_PATHS = [
  File.join(fixture_root, "app/assets/stylesheets"),
  File.join(fixture_root, "app/assets/images"),
  File.join(fixture_root, "app/assets/javascripts"),
  File.join(fixture_root, "vendor_assets/stylesheets"),
].select { |p| Dir.exist?(p) }

config = OpenStruct.new(
  paths: LOAD_PATHS, prefix: "/assets", version: "1",
  compilers: [
    ["text/css", Propshaft::Compiler::CssAssetUrls], ["text/css", Propshaft::Compiler::SourceMappingUrls],
    ["text/javascript", Propshaft::Compiler::JsAssetUrls], ["text/javascript", Propshaft::Compiler::SourceMappingUrls],
  ],
  output_path: nil, manifest_path: nil,
  integrity_hash_algorithm: nil, file_watcher: nil, relative_url_root: nil)

failures = []

Dir.mktmpdir do |gem_out|
  config.output_path = Pathname.new(gem_out)
  config.manifest_path = Pathname.new(File.join(gem_out, ".manifest.json"))
  Propshaft::Assembly.new(config).processor.process

  def tree_files(root)
    Dir.glob(File.join(root, "**", "*")).select { |f| File.file?(f) }
        .map { |f| f.delete_prefix(root) }.sort
  end

  gem_files = tree_files(gem_out)
  port_files = tree_files(port_output)

  if gem_files != port_files
    failures << "file sets differ:\n  gem only:  #{(gem_files - port_files).inspect}\n  port only: #{(port_files - gem_files).inspect}"
  end

  (gem_files & port_files).each do |rel|
    gem_b = File.binread(File.join(gem_out, rel))
    port_b = File.binread(File.join(port_output, rel))
    failures << "#{rel} content differs (gem #{gem_b.bytesize}B, port #{port_b.bytesize}B)" if gem_b != port_b
  end
end

if failures.empty?
  puts "REVERSE CHECK OK: propshaft 1.3.2 == propshaft_cr (#{port_output})"
else
  failures.each { |f| STDERR.puts "MISMATCH: #{f}" }
  exit 1
end
