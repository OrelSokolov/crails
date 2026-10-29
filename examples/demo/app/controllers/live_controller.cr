# /live — LiveView-страница: счётчик + live-список заметок.
# Контейнеры несут id + data-phx-session (наш HMAC-токен), дальше
# официальный phoenix_live_view.js делает join и морфит DOM.

class LiveController < ApplicationController
  @counter_id : String = ""
  @counter_token : String = ""
  @notes_id : String = ""
  @notes_token : String = ""

  def index
    @counter_id = "phx-#{new_live_id}"
    @counter_token = DEMO_LIVE.token.sign({
      id: @counter_id, view: "DemoCounterLive",
      session: {} of String => String,
    })
    @notes_id = "phx-#{new_live_id}"
    @notes_token = DEMO_LIVE.token.sign({
      id: @notes_id, view: "DemoNotesLive",
      session: {} of String => String,
    })
  end

  # Vendored JS bundles (phoenix.min.js / phoenix_live_view.min.js),
  # embedded into the binary at compile time.
  PHOENIX_JS = {{ read_file("lib/live_view_cr/assets/phoenix.min.js") }}
  PHOENIX_LV_JS = {{ read_file("lib/live_view_cr/assets/phoenix_live_view.min.js") }}

  def asset
    case params["file"].to_s
    when "phoenix.min.js"    then serve_js(PHOENIX_JS)
    when "phoenix_live_view.min.js" then serve_js(PHOENIX_LV_JS)
    else
      render(plain: "Not Found", status: 404)
    end
  end

  private def serve_js(body : String) : Nil
    render(plain: body, content_type: "text/javascript; charset=utf-8")
    response.headers["Cache-Control"] = "public, max-age=3600"
  end
end
