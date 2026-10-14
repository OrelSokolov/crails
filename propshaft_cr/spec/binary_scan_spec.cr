# Отклонение #2 закрыто: referenced_by сканирует и бинарные ассеты
# (invalid UTF-8) — ASCII url()-паттерны матчатся, как в ruby
# (ASCII-8BIT regex). Регрессия: раньше такие ассеты пропускались.

require "spec"
require "../src/propshaft_cr"
require "file_utils"

Propshaft.logger = IO::Memory.new

BIN_ROOT = File.join(Dir.tempdir, "crails_propshaft_bin_#{Random::Secure.hex(4)}")

def binary_load_path : Propshaft::LoadPath
  css_dir = File.join(BIN_ROOT, "stylesheets")
  img_dir = File.join(BIN_ROOT, "images")
  FileUtils.mkdir_p([css_dir, img_dir])
  # CSS c невалидными UTF-8 байтами вокруг url()-ссылки.
  File.write(File.join(css_dir, "app.css"),
    %(a { background: url("bg.png"); }\n\xFF\xFE\xFF))
  File.write(File.join(img_dir, "bg.png"), "\x89PNG\r\n\x1A\n\xFF\xFE")

  config = Propshaft::Config.new
  config.paths = [css_dir, img_dir]
  Propshaft::Assembly.new(config).load_path
end

describe "binary asset scan (referenced_by)" do
  it "resolves url() inside invalid-UTF8 content" do
    load_path = binary_load_path
    css = load_path.find("app.css").not_nil!
    css.content.valid_encoding?.should be_false

    references = load_path.find_referenced_by(css)
    references.map(&.logical_path).should contain("bg.png")
  end
end

Spec.after_suite { FileUtils.rm_rf(BIN_ROOT) }
