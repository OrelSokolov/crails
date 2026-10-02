# AssetTagHelper — byte-exact with actionview 8.1.4 (oracle: asset_*
# cases). Fingerprints/manifests come later (P1): plain
# /stylesheets|javascripts|images paths, like Rails without sprockets.

module ActionView
  module Helpers
    module AssetTagHelper
      include TagHelper

      def compute_asset_path(source : String) : String
        return source if source.starts_with?('/') || source.includes?("://")
        "/#{yield source}"
      end

      def stylesheet_link_tag(*sources : String, **opts) : SafeString
        SafeString.new(sources.map { |src|
          %(<link rel="stylesheet" href="#{compute_asset_path(src) { |s| "stylesheets/#{s}.css" }}"#{tag_options(opts)} />)
        }.join("\n"))
      end

      def javascript_include_tag(*sources : String, **opts) : SafeString
        SafeString.new(sources.map { |src|
          %(<script src="#{compute_asset_path(src) { |s| "javascripts/#{s}.js" }}"></script>)
        }.join("\n"))
      end

      def image_tag(source : String, **opts) : SafeString
        opts = __av_opts_to_h(opts)
        attrs = {} of String => AttrVal
        alt_opt = opts.delete("alt")
        attrs["alt"] = alt_opt if alt_opt
        attrs["src"] = compute_asset_path(source) { |s| "images/#{s}" }
        if size_opt = opts.delete("size")
          parts = size_opt.to_s.split("x", 2)
          attrs["width"] = parts[0]
          attrs["height"] = parts[1]? || parts[0]
        end
        attrs.merge!(opts)
        SafeString.new(%(<img#{tag_options(attrs)} />))
      end

      def favicon_link_tag(source : String = "favicon.ico", **opts) : SafeString
        href = compute_asset_path(source) { |s| "images/#{s}" }
        SafeString.new(%(<link rel="icon" type="image/x-icon" href="#{href}"#{tag_options(opts)} />))
      end

      def javascript_tag(content : String) : SafeString
        SafeString.new("<script>\n//<![CDATA[\n#{content}\n//]]>\n</script>")
      end
    end
  end
end
