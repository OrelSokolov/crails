# Oracle fixture builder — shared by oracle/propshaft_cases.rb (snapshot
# capture) and oracle/verify_propshaft.rb (reverse check: gem verifies the
# port's output). Deterministic: same tree on every run.

require "fileutils"

module PropshaftOracleFixture
  PNG = "\x89PNG\r\n\x1a\nfake-png-bytes"

  def self.build(root)
    stylesheets = File.join(root, "app/assets/stylesheets")
    images      = File.join(root, "app/assets/images")
    javascripts = File.join(root, "app/assets/javascripts")
    vendor      = File.join(root, "vendor_assets/stylesheets")
    ref_a       = File.join(root, "ref_a/stylesheets")
    ref_b       = File.join(root, "ref_b/stylesheets")
    FileUtils.rm_rf(root)
    [File.join(stylesheets, "deep"), File.join(stylesheets, "deep/sub"),
     images, javascripts, vendor, ref_a, ref_b].each { |d| FileUtils.mkdir_p(d) }

    File.write(File.join(stylesheets, "source.css"), <<~CSS)
      @import "other.css";
      .body {
        background: url("bg.png");
        icon: url('../images/i.png');
        plain: url(noquote.png);
        dot: url("./bg.png");
        root: url(/absolute-root.png);
        data: url("data:image/png;base64,AAA");
        hash: url("#frag");
        remote: url("https://x.example/a.png");
        proto: url("//cdn.example/b.png");
        query: url("bg.png?v=123");
        query_hash: url("bg.png#anchor");
        missing: url("missing.png");
      }
      //# sourceMappingURL=source.css.map
    CSS
    File.write(File.join(stylesheets, "missingmap.css"), "a { color: red; }\n//# sourceMappingURL=missing.css.map\n")
    File.write(File.join(stylesheets, "landing.css"), "/* app landing */\n")
    File.write(File.join(stylesheets, "bg.png"), PNG + "-bg")
    File.write(File.join(stylesheets, "noquote.png"), PNG + "-noquote")
    File.write(File.join(stylesheets, "source.css.map"), '{"version":3,"sources":["source.css"]}')
    File.write(File.join(stylesheets, ".dotfile.css"), "/* must not appear */")
    File.write(File.join(stylesheets, "deep/nested.css"), "a { background: url('sub/x.png'); missing: url('../bg2.png'); }\n")
    File.write(File.join(stylesheets, "deep/bg2.png"), PNG + "-bg2")
    File.write(File.join(stylesheets, "deep/sub/x.png"), PNG + "-x")
    File.write(File.join(stylesheets, "deep/sub/style.css"), "b { background: url('../bg2.png'); }\n")
    File.write(File.join(stylesheets, "noext"), "no extension here\n")
    File.write(File.join(stylesheets, "pre-abcdef12345.digested.css"), "/* predigested */\n")
    File.write(File.join(images, "i.png"), PNG + "-i")
    File.write(File.join(images, "absolute-root.png"), PNG + "-root")
    File.write(File.join(javascripts, "app.js"), <<~JS)
      const bg = RAILS_ASSET_URL("bg.png");
      const root = RAILS_ASSET_URL('/absolute-root.png');
      const missing = RAILS_ASSET_URL("missing.png");
      const data = RAILS_ASSET_URL("data:whatever");
      const remote = RAILS_ASSET_URL("https://x/y.png");
      const proto = RAILS_ASSET_URL("//cdn/z.png");
      const query = RAILS_ASSET_URL("bg.png?v=9");
      //# sourceMappingURL=app.js.map
    JS
    File.write(File.join(javascripts, "app.js.map"), '{"version":3,"sources":["app.js"]}')
    File.write(File.join(javascripts, "util.mjs"), "export const bg = RAILS_ASSET_URL(\"bg.png\");\n")
    File.write(File.join(vendor, "landing.css"), "/* vendor landing */\n")
    # Same css content, different referenced png → digests must differ
    # (content_with_compile_references cascade).
    File.write(File.join(ref_a, "cascade.css"), "a { background: url(" + "'x.png'); }\n")
    File.write(File.join(ref_a, "x.png"), PNG + "-a")
    File.write(File.join(ref_b, "cascade.css"), "a { background: url(" + "'x.png'); }\n")
    File.write(File.join(ref_b, "x.png"), PNG + "-b")

    [stylesheets, images, javascripts, vendor]
  end
end
