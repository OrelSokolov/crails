# Oracle cases for the propshaft port (Processor / LoadPath / Asset /
# Compilers / Manifest, propshaft 1.3.2).
#
# Run against the ORIGINAL gem:
#   GEM_HOME=../../.oracle-gems ruby oracle/propshaft_cases.rb \
#     > oracle/propshaft_expected.yml
#
# Each line: "<case_id>\t<value>". Mirrored 1:1 in
# spec/propshaft_spec.cr. The fixture tree is regenerated on every run
# (creation order deliberately differs from alphabetical order — it pins
# the readdir-order semantics of the manifest key order).
#
# Wire details pinned here (observed from the real gem, not from memory):
# - digest = SHA1(raw content + contents of referenced assets +
#   load_path.version), first 8 hex chars;
# - manifest = {"<logical>":{"digested_path":"...","integrity":null},...}
#   (compact JSON, insertion order = readdir order, no trailing newline);
# - digested_path inserts -<digest> before the final extension; a file
#   WITHOUT an extension gets no digest at all;
# - JS url rewriting matches RAILS_ASSET_URL("...") — NOT
#   new URL(..., import.meta.url) as the original plan assumed;
# - .mjs / .map have no Mime type in Rails 8.1.4 → pass-through copy.

gem "propshaft", "= 1.3.2"
gem "actionpack", "= 8.1.4"

require "rubygems"
require "ostruct"
require "fileutils"
require "json"
require "pathname"

gem_dir = Gem::Specification.find_by_name("propshaft", "= 1.3.2").gem_dir
$LOAD_PATH.unshift(File.join(gem_dir, "lib"))
# normally loaded by rails:
require "active_support/core_ext/object/blank"
require "active_support/core_ext/string/starts_ends_with"
require "active_support/core_ext/string/access"
require "active_support/core_ext/enumerable" # Set#exclude?
require "propshaft"
require "propshaft/resolver/dynamic"

# Keep the snapshot clean: the gem logs Writing/Unable-to-resolve to STDOUT.
Propshaft.logger = Logger.new(File::NULL)

def render(v)
  case v
  when String then v.gsub("\n", "\\n")
  else v.inspect
  end
end

def case_run(id)
  puts "#{id}\t#{render(yield)}"
rescue StandardError => e
  puts "#{id}\traise:#{e.class.name}"
end

require_relative "fixture"
ROOT    = File.expand_path("propshaft_fixture", __dir__)
OUTPUT  = File.join(ROOT, "public", "assets")
LOAD_PATHS = PropshaftOracleFixture.build(ROOT)
REF_A = File.join(ROOT, "ref_a/stylesheets")
REF_B = File.join(ROOT, "ref_b/stylesheets")

def build_assembly(paths, version: "1", integrity_hash_algorithm: nil, output_path: OUTPUT)
  OpenStruct.new(
    paths: paths,
    prefix: "/assets",
    version: version,
    compilers: [
      ["text/css", Propshaft::Compiler::CssAssetUrls],
      ["text/css", Propshaft::Compiler::SourceMappingUrls],
      ["text/javascript", Propshaft::Compiler::JsAssetUrls],
      ["text/javascript", Propshaft::Compiler::SourceMappingUrls],
    ],
    output_path: Pathname.new(output_path),
    manifest_path: Pathname.new(File.join(output_path, ".manifest.json")),
    integrity_hash_algorithm: integrity_hash_algorithm,
    file_watcher: nil,
    relative_url_root: nil,
  ).then { |config| Propshaft::Assembly.new(config) }
end

ASSEMBLY   = build_assembly(LOAD_PATHS)
LOAD_PATH  = ASSEMBLY.load_path
MANIFEST_H = LOAD_PATH.manifest # in-memory manifest (hash logical → entry)

# --- Processor#process on the real fixture -----------------------------------

ASSEMBLY.processor.process

case_run("process_files") do
  Dir.glob("#{OUTPUT}/**/*", File::FNM_DOTMATCH).select { |f| File.file?(f) }
     .map { |f| f.delete_prefix("#{OUTPUT}/") }.sort
end
case_run("manifest_raw") { File.read(File.join(OUTPUT, ".manifest.json")) }
case_run("css_compiled") do
  File.read(File.join(OUTPUT, MANIFEST_H["source.css"].digested_path))
end
case_run("css_missingmap_compiled") do
  File.read(File.join(OUTPUT, MANIFEST_H["missingmap.css"].digested_path))
end
case_run("js_compiled") do
  File.read(File.join(OUTPUT, MANIFEST_H["app.js"].digested_path))
end
case_run("mjs_passthrough") do
  File.read(File.join(OUTPUT, MANIFEST_H["util.mjs"].digested_path))
end
case_run("map_copied") do
  File.read(File.join(OUTPUT, MANIFEST_H["source.css.map"].digested_path))
end
case_run("png_copied") do
  File.binread(File.join(OUTPUT, MANIFEST_H["deep/bg2.png"].digested_path)).unpack1("H*")
end

# --- Asset --------------------------------------------------------------------

case_run("digest_source")    { LOAD_PATH.find("source.css").digest }
case_run("digest_landing")   { LOAD_PATH.find("landing.css").digest }
case_run("digest_noext")     { LOAD_PATH.find("noext").digest }
case_run("noext_digested_path") { LOAD_PATH.find("noext").digested_path.to_s }
case_run("predigested_digested_path") do
  LOAD_PATH.find("pre-abcdef12345.digested.css").digested_path.to_s
end
case_run("digested_path_source") { LOAD_PATH.find("source.css").digested_path.to_s }
case_run("digested_path_map") { LOAD_PATH.find("app.js.map").digested_path.to_s }
case_run("fresh_ok")   { !!LOAD_PATH.find("source.css").fresh?(LOAD_PATH.find("source.css").digest) }
case_run("fresh_wrong") { !!LOAD_PATH.find("source.css").fresh?("deadbeef") }
case_run("fresh_nil_digest") { !!LOAD_PATH.find("source.css").fresh?(nil) }
case_run("fresh_predigested") do
  !!LOAD_PATH.find("pre-abcdef12345.digested.css").fresh?("deadbeef")
end
case_run("integrity_sha384") do
  LOAD_PATH.find("source.css").integrity(hash_algorithm: "sha384")
end
case_run("integrity_sha256") do
  LOAD_PATH.find("source.css").integrity(hash_algorithm: "sha256")
end

# --- LoadPath -----------------------------------------------------------------

case_run("find_missing") { LOAD_PATH.find("missing.css") }
case_run("assets_count") { LOAD_PATH.assets.size }
case_run("assets_logical_sorted_head") { LOAD_PATH.assets.map(&:logical_path).sort.first(5) }
case_run("duplicate_landing") do
  File.read(File.join(OUTPUT, MANIFEST_H["landing.css"].digested_path))
end

# --- digest inputs: version + reference cascade -------------------------------

case_run("version_1") { build_assembly(LOAD_PATHS, version: "1").load_path.find("landing.css").digest }
case_run("version_2") { build_assembly(LOAD_PATHS, version: "2").load_path.find("landing.css").digest }
case_run("ref_cascade_a") { build_assembly([REF_A]).load_path.find("cascade.css").digest }
case_run("ref_cascade_b") { build_assembly([REF_B]).load_path.find("cascade.css").digest }
case_run("ref_cascade_css_only") do
  build_assembly([REF_A]).load_path.find("x.png").digest
end

# --- extract_path_and_digest ---------------------------------------------------

{
  "extract_plain"        => "source.css",
  "extract_digested"     => "source-9c3efd7b.css",
  "extract_nested"       => "deep/bg2-1234567890abcdef.map",
  "extract_predigested"  => "pre-abcdef12345.digested.css",
  "extract_noext"        => "noext",
  "extract_short_digest" => "a-abc.css",
}.each do |id, path|
  case_run(id) { Propshaft::Asset.extract_path_and_digest(path).inspect }
end

# --- errors --------------------------------------------------------------------

case_run("missing_error_message") { Propshaft::MissingAssetError.new("foo.css").message }

# --- manifest with integrity ----------------------------------------------------

case_run("manifest_integrity_json") do
  mp = Propshaft::Manifest.new(integrity_hash_algorithm: "sha384")
  mp.push_asset(LOAD_PATH.find("landing.css"))
  mp.push_asset(LOAD_PATH.find("noext"))
  mp.to_json
end

# --- legacy manifest format read -------------------------------------------------

case_run("manifest_legacy_read") do
  legacy = File.join(ROOT, "legacy_manifest.json")
  File.write(legacy, '{"a.css":"a-11111111.css","b.css":{"digested_path":"b-22222222.css","integrity":"sha384-xyz"}}')
  m = Propshaft::Manifest.from_path(Pathname.new(legacy))
  [m["a.css"].digested_path, m["a.css"].integrity, m["b.css"].digested_path, m["b.css"].integrity].inspect
end

# --- resolvers (used by view helpers in phase 3) ---------------------------------

case_run("resolver_static") do
  r = Propshaft::Resolver::Static.new(
    manifest_path: Pathname.new(File.join(OUTPUT, ".manifest.json")), prefix: "/assets")
  [r.resolve("source.css"), r.resolve("missing.css"), r.resolve("noext")].inspect
end
case_run("resolver_dynamic") do
  r = Propshaft::Resolver::Dynamic.new(load_path: LOAD_PATH, prefix: "/assets")
  [r.resolve("source.css"), r.resolve("missing.css")].inspect
end
case_run("resolver_static_read") do
  r = Propshaft::Resolver::Static.new(
    manifest_path: Pathname.new(File.join(OUTPUT, ".manifest.json")), prefix: "/assets")
  r.read("source.css").encoding.to_s
end

# --- second process run is a no-op (incremental) ---------------------------------

case_run("second_process_noop") do
  before = Dir.glob("#{OUTPUT}/**/*").select { |f| File.file?(f) }
              .map { |f| [f, File.mtime(f)] }
  sleep 0.05
  build_assembly(LOAD_PATHS).processor.process
  after = Dir.glob("#{OUTPUT}/**/*").select { |f| File.file?(f) }
             .map { |f| [f, File.mtime(f)] }
  before == after
end

# --- OutputPath#clean --------------------------------------------------------------

case_run("clean_removes_stale") do
  out2 = File.join(ROOT, "public", "clean_assets")
  FileUtils.mkdir_p(out2)
  asm = build_assembly(LOAD_PATHS, output_path: out2)
  asm.processor.process
  # two stale versions: one aged beyond the 1h expiry, one fresh;
  # clean(1, 1h) keeps the fresh one and removes the aged one.
  aged = File.join(out2, "landing-deadbeef.css")
  File.write(aged, "stale")
  File.utime(Time.now - 7200, Time.now - 7200, aged)
  fresh = File.join(out2, "loading-11111111.css")
  File.write(fresh, "stale but fresh")
  Propshaft::OutputPath.new(Pathname.new(out2), asm.load_path.manifest).clean(1, 3600)
  [File.exist?(aged), File.exist?(fresh),
   File.exist?(File.join(out2, MANIFEST_H["landing.css"].digested_path))]
end
