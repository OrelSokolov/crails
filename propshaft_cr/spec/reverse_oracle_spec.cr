# Реверс-проверка (AGENTS.md): порт собирает фикстуру, настоящий гем
# (propshaft 1.3.2, oracle/verify_propshaft.rb) проверяет выход
# побайтово. ruby (+GEM_HOME с гемом) должен быть в PATH; иначе — skip
# с инструкцией. Полный gate на машине без локального ruby:
#   crystal run spec/reverse_runner.cr -- OUT_DIR   # контейнер/хост с crystal
#   ruby oracle/verify_propshaft.rb spec/reverse_fixture OUT_DIR

require "spec"
require "../src/propshaft_cr"
require "./fixture"
require "file_utils"

Propshaft.logger = IO::Memory.new

REVERSE_ROOT = File.join(Dir.tempdir, "crails_propshaft_reverse_#{Random::Secure.hex(4)}")
REVERSE_OUT = File.join(REVERSE_ROOT, "public", "assets")

describe "reverse oracle: gem verifies port output" do
  it "byte-identical to propshaft 1.3.2 output" do
    load_paths = PropshaftSpecFixture.build(REVERSE_ROOT)
    config = Propshaft::Config.new
    config.paths = load_paths
    config.version = "1"
    config.output_path = REVERSE_OUT
    config.manifest_path = File.join(REVERSE_OUT, ".manifest.json")
    Propshaft::Assembly.new(config).processor.process

    ruby = begin
      Process.run("ruby", {"-v"}, output: Process::Redirect::Close,
        error: Process::Redirect::Close).success?
    rescue File::NotFoundError
      false
    end
    unless ruby
      pending! "ruby not in PATH (run oracle/verify_propshaft.rb manually)"
      next
    end
    status = Process.run("ruby", {File.join(__DIR__, "..", "oracle", "verify_propshaft.rb"),
      REVERSE_ROOT, REVERSE_OUT}, output: :inherit, error: :inherit)
    status.success?.should be_true
  end
end

Spec.after_suite { FileUtils.rm_rf(REVERSE_ROOT) }
