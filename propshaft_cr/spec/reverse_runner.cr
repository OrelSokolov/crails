# Ручной gate реверс-проверки (если ruby недоступен рядом с crystal):
#   crystal run spec/reverse_runner.cr -- OUT_DIR [FIXTURE_DIR]
# затем на машине с ruby 3.4 + GEM_HOME гема:
#   ruby oracle/verify_propshaft.rb FIXTURE_DIR OUT_DIR
#
# FIXTURE_DIR по умолчанию — oracle/reverse_fixture (создаётся здесь).

require "../src/propshaft_cr"
require "./fixture"
require "file_utils"

Propshaft.logger = STDERR

out_dir = ARGV[0]? || abort "usage: reverse_runner.cr OUT_DIR [FIXTURE_DIR]"
fixture = ARGV[1]? || File.join(__DIR__, "..", "oracle", "reverse_fixture")

load_paths = PropshaftSpecFixture.build(File.expand_path(fixture))
config = Propshaft::Config.new
config.paths = load_paths
config.version = "1"
config.output_path = out_dir
config.manifest_path = File.join(out_dir, ".manifest.json")
Propshaft::Assembly.new(config).processor.process
puts "port output: #{out_dir}"
puts "fixture:     #{File.expand_path(fixture)}"
