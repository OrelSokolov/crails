# Vendored JS (@hotwired/turbo + cable-connector), встроенные в
# бинарник на этапе компиляции — тот же паттерн, что у live-ассетов.

class AssetsController < ApplicationController
  TURBO_JS       = {{ read_file("public/turbo.js") }}
  TURBO_CABLE_JS = {{ read_file("public/turbo_cable.js") }}

  def show
    case params["file"].to_s
    when "turbo.js"       then serve_js(TURBO_JS)
    when "turbo_cable.js" then serve_js(TURBO_CABLE_JS)
    else
      render(plain: "Not Found", status: 404)
    end
  end

  private def serve_js(body : String) : Nil
    render(plain: body, content_type: "text/javascript; charset=utf-8")
    response.headers["Cache-Control"] = "public, max-age=3600"
  end
end
