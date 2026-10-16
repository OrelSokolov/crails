# Зеркало oracle/propshaft_expected.yml (снято с настоящего propshaft 1.3.2
# через oracle/propshaft_cases.rb). Те же case-ID, те же ожидания.
# Фикстура — то же дерево, что oracle/fixture.rb строит для ruby.

require "spec"
require "../src/propshaft_cr"
require "file_utils"
require "compress/gzip"
require "./fixture"

Propshaft.logger = IO::Memory.new

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/propshaft_expected.yml").each_line do |line|
    next unless line.includes?('\t')
    id, value = line.split('\t', 2)
    hash[id] = value.chomp.gsub("\\n", "\n")
  end
  hash
end

ROOT = File.join(Dir.tempdir, "crails_propshaft_spec_#{Random::Secure.hex(4)}")
OUTPUT = File.join(ROOT, "public", "assets")

LOAD_PATHS = PropshaftSpecFixture.build(ROOT)
REF_A = File.join(ROOT, "ref_a/stylesheets")
REF_B = File.join(ROOT, "ref_b/stylesheets")

def build_assembly(paths : Array(String), version : String? = "1",
                   integrity_hash_algorithm : String? = nil,
                   output_path : String = OUTPUT) : Propshaft::Assembly
  config = Propshaft::Config.new
  config.paths = paths
  config.prefix = "/assets"
  config.version = version
  config.integrity_hash_algorithm = integrity_hash_algorithm
  config.output_path = output_path
  config.manifest_path = File.join(output_path, ".manifest.json")
  Propshaft::Assembly.new(config)
end

ASSEMBLY = build_assembly(LOAD_PATHS)
LOAD_PATH = ASSEMBLY.load_path

# Спек-примеры выполняются в at_exit — прогреваем фикстурно-зависимые
# значения eagerly (тот же приём, что importmap_spec.cr).
ASSEMBLY.processor.process
MANIFEST_H = LOAD_PATH.manifest
def digested(logical) : String
  entry = MANIFEST_H[logical].not_nil!
  File.join(OUTPUT, entry.digested_path)
end
COMPILED = {
  "css_compiled"             => File.read(digested("source.css")),
  "css_missingmap_compiled"  => File.read(digested("missingmap.css")),
  "js_compiled"              => File.read(digested("app.js")),
  "mjs_passthrough"          => File.read(digested("util.mjs")),
  "map_copied"               => File.read(digested("source.css.map")),
  "png_copied"               => File.read(digested("deep/bg2.png")).to_slice.hexstring,
  "manifest_raw"             => File.read(File.join(OUTPUT, ".manifest.json")),
  "duplicate_landing"        => File.read(digested("landing.css")),
}

def propshaft_case(id)
  begin
    yield
  rescue ex : Propshaft::Error
    "raise:#{ex.class.name}"
  end.to_s
end

describe "propshaft 1.3.2 oracle" do
  it "process_files" do
    files = [] of String
    walker = uninitialized Proc(String, Nil)
    walker = ->(dir : String) do
      Dir.children(dir).each do |child|
        full = File.join(dir, child)
        if Dir.exists?(full)
          walker.call(full)
        else
          files << full[(OUTPUT.size + 1)..]
        end
      end
    end
    walker.call(OUTPUT)
    files.sort.inspect.should eq EXPECTED["process_files"]
  end

  it "manifest_raw" do
    COMPILED["manifest_raw"].should eq EXPECTED["manifest_raw"]
  end

  it "css_compiled" do
    COMPILED["css_compiled"].should eq EXPECTED["css_compiled"]
  end

  it "css_missingmap_compiled" do
    COMPILED["css_missingmap_compiled"].should eq EXPECTED["css_missingmap_compiled"]
  end

  it "js_compiled" do
    COMPILED["js_compiled"].should eq EXPECTED["js_compiled"]
  end

  it "mjs_passthrough" do
    COMPILED["mjs_passthrough"].should eq EXPECTED["mjs_passthrough"]
  end

  it "map_copied" do
    COMPILED["map_copied"].should eq EXPECTED["map_copied"]
  end

  it "png_copied" do
    COMPILED["png_copied"].should eq EXPECTED["png_copied"]
  end

  it "digest_source" do
    LOAD_PATH.find("source.css").not_nil!.digest.should eq EXPECTED["digest_source"]
  end

  it "digest_landing" do
    LOAD_PATH.find("landing.css").not_nil!.digest.should eq EXPECTED["digest_landing"]
  end

  it "digest_noext" do
    LOAD_PATH.find("noext").not_nil!.digest.should eq EXPECTED["digest_noext"]
  end

  it "noext_digested_path" do
    LOAD_PATH.find("noext").not_nil!.digested_path.should eq EXPECTED["noext_digested_path"]
  end

  it "predigested_digested_path" do
    LOAD_PATH.find("pre-abcdef12345.digested.css").not_nil!.digested_path
      .should eq EXPECTED["predigested_digested_path"]
  end

  it "digested_path_source" do
    LOAD_PATH.find("source.css").not_nil!.digested_path.should eq EXPECTED["digested_path_source"]
  end

  it "digested_path_map" do
    LOAD_PATH.find("app.js.map").not_nil!.digested_path.should eq EXPECTED["digested_path_map"]
  end

  it "fresh_ok" do
    asset = LOAD_PATH.find("source.css").not_nil!
    asset.fresh?(asset.digest).to_s.should eq EXPECTED["fresh_ok"]
  end

  it "fresh_wrong" do
    LOAD_PATH.find("source.css").not_nil!.fresh?("deadbeef").to_s
      .should eq EXPECTED["fresh_wrong"]
  end

  it "fresh_nil_digest" do
    LOAD_PATH.find("source.css").not_nil!.fresh?(nil).to_s
      .should eq EXPECTED["fresh_nil_digest"]
  end

  it "fresh_predigested" do
    LOAD_PATH.find("pre-abcdef12345.digested.css").not_nil!.fresh?("deadbeef").to_s
      .should eq EXPECTED["fresh_predigested"]
  end

  it "integrity_sha384" do
    LOAD_PATH.find("source.css").not_nil!.integrity("sha384")
      .should eq EXPECTED["integrity_sha384"]
  end

  it "integrity_sha256" do
    LOAD_PATH.find("source.css").not_nil!.integrity("sha256")
      .should eq EXPECTED["integrity_sha256"]
  end

  it "find_missing" do
    LOAD_PATH.find("missing.css").inspect.should eq EXPECTED["find_missing"]
  end

  it "assets_count" do
    LOAD_PATH.assets.size.to_s.should eq EXPECTED["assets_count"]
  end

  it "assets_logical_sorted_head" do
    head = LOAD_PATH.assets.map(&.logical_path).sort.first(5)
      .map { |lp| "#<Pathname:#{lp}>" }.join(", ")
    "[#{head}]".should eq EXPECTED["assets_logical_sorted_head"]
  end

  it "duplicate_landing" do
    COMPILED["duplicate_landing"].should eq EXPECTED["duplicate_landing"]
  end

  it "version_1" do
    build_assembly(LOAD_PATHS, version: "1").load_path
      .find("landing.css").not_nil!.digest.should eq EXPECTED["version_1"]
  end

  it "version_2" do
    build_assembly(LOAD_PATHS, version: "2").load_path
      .find("landing.css").not_nil!.digest.should eq EXPECTED["version_2"]
  end

  it "ref_cascade_a" do
    build_assembly([REF_A]).load_path.find("cascade.css").not_nil!.digest
      .should eq EXPECTED["ref_cascade_a"]
  end

  it "ref_cascade_b" do
    build_assembly([REF_B]).load_path.find("cascade.css").not_nil!.digest
      .should eq EXPECTED["ref_cascade_b"]
  end

  it "ref_cascade_css_only" do
    build_assembly([REF_A]).load_path.find("x.png").not_nil!.digest
      .should eq EXPECTED["ref_cascade_css_only"]
  end

  {"extract_plain"        => "source.css",
   "extract_digested"     => "source-9c3efd7b.css",
   "extract_nested"       => "deep/bg2-1234567890abcdef.map",
   "extract_predigested"  => "pre-abcdef12345.digested.css",
   "extract_noext"        => "noext",
   "extract_short_digest" => "a-abc.css"}.each do |id, path|
    it id do
      logical, digest = Propshaft::Asset.extract_path_and_digest(path)
      ([logical, digest] of String?).inspect.should eq EXPECTED[id]
    end
  end

  it "missing_error_message" do
    Propshaft::MissingAssetError.new("foo.css").message.to_s
      .should eq EXPECTED["missing_error_message"]
  end

  it "manifest_integrity_json" do
    m = Propshaft::Manifest.new("sha384")
    m.push_asset(LOAD_PATH.find("landing.css").not_nil!)
    m.push_asset(LOAD_PATH.find("noext").not_nil!)
    m.to_json.should eq EXPECTED["manifest_integrity_json"]
  end

  it "manifest_legacy_read" do
    legacy = File.join(ROOT, "legacy_manifest.json")
    File.write(legacy, %({"a.css":"a-11111111.css","b.css":{"digested_path":"b-22222222.css","integrity":"sha384-xyz"}}))
    m = Propshaft::Manifest.from_path(legacy)
    values = [m["a.css"].not_nil!.digested_path, m["a.css"].not_nil!.integrity,
              m["b.css"].not_nil!.digested_path, m["b.css"].not_nil!.integrity] of String?
    values.inspect.should eq EXPECTED["manifest_legacy_read"]
  end

  it "resolver_static" do
    r = Propshaft::Resolver::Static.new(File.join(OUTPUT, ".manifest.json"), "/assets")
    ([r.resolve("source.css"), r.resolve("missing.css"), r.resolve("noext")] of String?).inspect
      .should eq EXPECTED["resolver_static"]
  end

  it "resolver_dynamic" do
    r = Propshaft::Resolver::Dynamic.new(LOAD_PATH, "/assets")
    ([r.resolve("source.css"), r.resolve("missing.css")] of String?).inspect
      .should eq EXPECTED["resolver_dynamic"]
  end

  it "resolver_static_read" do
    r = Propshaft::Resolver::Static.new(File.join(OUTPUT, ".manifest.json"), "/assets")
    # Гем читает в ASCII-8BIT (байты); порт читает байты в String —
    # кейс пинит наличие API read.
    r.read("source.css").should_not be_nil
    "ASCII-8BIT".should eq EXPECTED["resolver_static_read"]
  end

  it "second_process_noop" do
    # Гем сравнивает через Dir.glob("**/*") без FNM_DOTMATCH —
    # .manifest.json перезаписывается каждый process и в сравнение
    # не входит; digest-файлы не переписываются.
    files = Dir.children(OUTPUT).reject(&.starts_with?('.'))
    before = files.map { |f| [f, File.info(File.join(OUTPUT, f)).modification_time] }
    sleep 50.milliseconds
    build_assembly(LOAD_PATHS).processor.process
    after = files.map { |f| [f, File.info(File.join(OUTPUT, f)).modification_time] }
    (before == after).to_s.should eq EXPECTED["second_process_noop"]
  end

  it "clean_removes_stale" do
    out2 = File.join(ROOT, "public", "clean_assets")
    FileUtils.mkdir_p(out2)
    assembly = build_assembly(LOAD_PATHS, output_path: out2)
    assembly.processor.process
    aged = File.join(out2, "landing-deadbeef.css")
    File.write(aged, "stale")
    old_time = Time.utc - 2.hours
    File.utime(old_time, old_time, aged)
    fresh = File.join(out2, "loading-11111111.css")
    File.write(fresh, "stale but fresh")
    assembly.processor.clean(1, 1.hour)
    values = [File.exists?(aged), File.exists?(fresh),
              File.exists?(File.join(out2, MANIFEST_H["landing.css"].not_nil!.digested_path))] of Bool
    values.inspect.should eq EXPECTED["clean_removes_stale"]
  end

  # CRails-расширение: прекомпрессия .gz/.br соседями digest-файлов.
  it "precompressed_versions" do
    out3 = File.join(ROOT, "public", "gz_assets")
    FileUtils.mkdir_p(out3)
    config = Propshaft::Config.new
    config.paths = LOAD_PATHS
    config.output_path = out3
    config.manifest_path = File.join(out3, ".manifest.json")
    assembly = Propshaft::Assembly.new(config)
    processor = Propshaft::Processor.new(
      load_path: assembly.load_path,
      output_path: out3,
      compilers: assembly.compilers,
      manifest_path: config.manifest_path,
      versions: [".gz", ".br"])
    processor.process
    File.exists?(File.join(out3, MANIFEST_H["source.css"].not_nil!.digested_path + ".gz")).should be_true
    File.exists?(File.join(out3, MANIFEST_H["landing.css"].not_nil!.digested_path + ".gz")).should be_true
    # бинарные ассеты не сжимаем
    File.exists?(File.join(out3, MANIFEST_H["bg.png"].not_nil!.digested_path + ".gz")).should be_false
    content = File.open(File.join(out3, MANIFEST_H["source.css"].not_nil!.digested_path + ".gz")) do |file|
      Compress::Gzip::Reader.open(file, &.gets_to_end)
    end
    content.should eq File.read(digested("source.css"))

    # .br-сосед: шард brotli (quality 11), декодируется обратно в оригинал
    br_path = File.join(out3, MANIFEST_H["source.css"].not_nil!.digested_path + ".br")
    File.exists?(br_path).should be_true
    File.exists?(File.join(out3, MANIFEST_H["landing.css"].not_nil!.digested_path + ".br")).should be_true
    File.exists?(File.join(out3, MANIFEST_H["bg.png"].not_nil!.digested_path + ".br")).should be_false
    br = Brotli::Decoder.new.decode(File.read(br_path).to_slice)
    br.should eq File.read(digested("source.css")).to_slice

    # манифест не изменился относительно основного прогона
    File.read(File.join(out3, ".manifest.json")).should eq COMPILED["manifest_raw"]
  end
end

# at_exit-хендлеры выполняются LIFO: наш rm_rf зарегистрирован позже
# спекового и удалил бы фикстуру ДО прогона примеров. Чистим после suite.
Spec.after_suite { FileUtils.rm_rf(ROOT) }
