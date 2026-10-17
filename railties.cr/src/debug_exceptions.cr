# ActionDispatch::DebugExceptions port (Rails 8.1.4): the development
# HTML error pages rendered by Middleware::ShowExceptions when a request
# fails. Oracle — the Rails 8.1 dev pages:
#   * Routing Error: "No route matches [GET] \"/path\"", CRails.root and
#     the full routes table (Helper / HTTP Verb / Path /
#     Controller#Action / Source Location, priority top-to-bottom,
#     search filter);
#   * internal errors: exception class + message, Application Trace /
#     Framework Trace / Full Trace tabs, request parameters and the raw
#     request body.
# Deviations from Rails (deliberate):
#   * theme is demo's светлая серо-голубая палитра instead of the red
#     header (demo/README: «светлая серо-голубая тема»);
#   * params are re-parsed at middleware level (route match + query +
#     body) — the controller's own params live inside the Dispatcher;
#   * no editor links in traces, no "Local variables" extraction.
#
# Test/production keep the bare ShowExceptions responses; these pages are
# rendered only when CRails.env.development?.

module CRails
  module DebugExceptions
    # demo palette (demo/app/views/layouts/application.html.erb).
    TEXT   = "#24303f"
    MUTED  = "#64748b"
    ACCENT = "#095a8d"
    BG     = "#eef2f7"
    CARD   = "#ffffff"
    BORDER = "#d8e0ea"
    SOFT   = "#f4f8fc"

    # Raw body longer than this is truncated on the page (still re-fed
    # to the request in full).
    MAX_BODY_DISPLAY = 16_000

    # The dev 404 Routing Error page: message + routes table.
    def self.routing_error_page(context : HTTP::Server::Context,
                                ex : ActionController::RoutingError,
                                app : CRails::Application?) : String
      message = ex.message.to_s
      String.build do |io|
        page(io, "Routing Error", message) do |body|
          body << "<p class=\"root\">CRails.root: " << HTML.escape(CRails.root) << "</p>"
          body << routes_table(app)
        end
      end
    end

    # The dev 500 page: exception, trace tabs, params and request body.
    def self.internal_error_page(context : HTTP::Server::Context,
                                 ex : Exception,
                                 app : CRails::Application?) : String
      params = request_params(context, app)
      raw_body = peek_body(context)
      String.build do |io|
        page(io, ex.class.name.to_s, ex.message.to_s) do |body|
          body << trace_tabs(ex)
          body << params_card(context, params)
          body << body_card(context, raw_body)
        end
      end
    end

    # --- page chrome -----------------------------------------------------

    private def self.page(io : IO, title : String, message : String, &) : Nil
      io << %(<!doctype html><html><head><meta charset="utf-8">) \
         << %(<meta name="viewport" content="width=device-width, initial-scale=1">) \
         << %(<title>) << HTML.escape(title) << %(</title><style>) \
         << STYLE \
         << %(</style></head><body><header class="top"><h1>) << HTML.escape(title)
      io << %(</h1></header><main>) << %(<div class="card msg"><p>) << HTML.escape(message) << %(</p></div>)
      yield io
      io << %(</main></body></html>)
    end

    private STYLE = <<-CSS
      body { margin: 0; background: #{BG}; color: #{TEXT};
             font: 14px/1.5 -apple-system, "Segoe UI", Roboto, sans-serif; }
      .top { background: #{ACCENT}; padding: 10px 24px; }
      .top h1 { color: #fff; font-size: 16px; margin: 0; font-weight: 600; }
      main { padding: 20px 24px 40px; max-width: 1080px; margin: 0 auto; }
      .card { background: #{CARD}; border: 1px solid #{BORDER}; border-radius: 8px;
              padding: 14px 18px; margin-bottom: 16px; }
      .card h2 { font-size: 13px; text-transform: uppercase; letter-spacing: .04em;
                 color: #{MUTED}; margin: 0 0 10px; font-weight: 600; }
      .card h2 small { text-transform: none; letter-spacing: 0; font-weight: 400; }
      .msg p { margin: 0; font-size: 15px; word-break: break-word; }
      .root { color: #{MUTED}; margin: 0 0 16px; font-size: 13px; }
      table { border-collapse: collapse; width: 100%; font-size: 13px; }
      th, td { text-align: left; padding: 6px 10px; border-bottom: 1px solid #{BORDER};
               vertical-align: top; white-space: nowrap; }
      th { color: #{MUTED}; font-weight: 600; background: #{SOFT}; }
      tr:hover td { background: #{SOFT}; }
      code { font: 12px/1.4 ui-monospace, "SF Mono", Menlo, Consolas, monospace; }
      td code, .msg code { background: #{SOFT}; border: 1px solid #{BORDER};
                           border-radius: 4px; padding: 1px 5px; }
      input[type="search"] { width: 240px; max-width: 100%; padding: 5px 10px;
              border: 1px solid #{BORDER}; border-radius: 6px; color: #{TEXT};
              background: #{CARD}; font-size: 13px; margin-bottom: 10px; }
      .tabs { margin-bottom: 12px; }
      .tabs button { border: 1px solid #{BORDER}; background: #{CARD}; color: #{MUTED};
              padding: 4px 12px; font-size: 13px; cursor: pointer; }
      .tabs button:first-child { border-radius: 6px 0 0 6px; }
      .tabs button:last-child { border-radius: 0 6px 6px 0; }
      .tabs button.active { background: #{ACCENT}; border-color: #{ACCENT}; color: #fff; }
      pre { margin: 0; padding: 10px 12px; background: #{SOFT};
            border: 1px solid #{BORDER}; border-radius: 6px; overflow-x: auto;
            font: 12px/1.5 ui-monospace, "SF Mono", Menlo, Consolas, monospace;
            white-space: pre-wrap; word-break: break-word; }
    CSS

    # --- routes table (Routing Error page) -------------------------------

    # The routes table exactly like the Rails dev page: helper names,
    # verb, path, controller#action and the config/routes.rb source line,
    # one row per route, priority top-to-bottom. The search input filters
    # rows client-side (no assets — pages are self-contained).
    private def self.routes_table(app : CRails::Application?) : String
      routes = app.try(&.routes.routes) || [] of Routes::Route
      String.build do |io|
        io << %(<div class="card"><h2>Routes <small>&mdash; match in priority from top to bottom</small></h2>) \
           << %(<input type="search" placeholder="Search" oninput=") \
           << "var q=this.value.toLowerCase();"
        io << "document.querySelectorAll('#croutes tbody tr').forEach(function(tr){"
        io << "tr.style.display = tr.textContent.toLowerCase().indexOf(q) > -1 ? '' : 'none';})"
        io << %("><table id="croutes"><thead><tr>) \
           << %(<th>Helper (Path / Url)</th><th>HTTP Verb</th><th>Path</th>) \
           << %(<th>Controller#Action</th><th>Source Location</th></tr></thead><tbody>)
        routes.each do |route|
          io << "<tr><td>"
          if name = route.name
            io << "<code>" << HTML.escape(name) << "_path</code> / <code>"
            io << HTML.escape(name) << "_url</code>"
          end
          io << "</td><td>" << HTML.escape(route.verb) \
             << "</td><td><code>" << HTML.escape(route.pattern) << "</code>" \
             << "</td><td>" << HTML.escape(route.controller) << "#" << HTML.escape(route.action)
          io << "</td><td>"
          io << HTML.escape(route.source.not_nil!) if route.source
          io << "</td></tr>"
        end
        io << %(</tbody></table></div>)
      end
    end

    # --- 500 page cards ---------------------------------------------------

    # Application Trace | Framework Trace | Full Trace, like the Rails
    # page. Application = frames of the app's own code, framework = the
    # rest (stdlib, framework shards). Frames may be relative (compiled
    # from the app dir — then everything outside lib/ is app code) or
    # absolute under CRails.root.
    private def self.trace_tabs(ex : Exception) : String
      trace = ex.backtrace? || [] of String
      app_trace = trace.select { |line| app_frame?(line) }
      framework_trace = trace.reject { |line| app_frame?(line) }
      String.build do |io|
        io << %(<div class="card"><div class="tabs">) \
           << %(<button id="tab-app" onclick="cshow('app')">Application Trace</button>) \
           << %(<button id="tab-fw" onclick="cshow('fw')">Framework Trace</button>) \
           << %(<button id="tab-full" onclick="cshow('full')">Full Trace</button>) \
           << %(</div>)
        io << %(<pre id="trace-app">) << HTML.escape(app_trace.join('\n')) << %(</pre>) \
           << %(<pre id="trace-fw" style="display:none">) << HTML.escape(framework_trace.join('\n')) << %(</pre>) \
           << %(<pre id="trace-full" style="display:none">) << HTML.escape(trace.join('\n')) << %(</pre>)
        io << "<script>function cshow(which){['app','fw','full'].forEach(function(k){"
        io << "document.getElementById('trace-'+k).style.display=k==which?'':'none';"
        io << "document.getElementById('tab-'+k).className=k==which?'active':'';});}"
        io << "</script></div>"
      end
    end

    private def self.app_frame?(line : String) : Bool
      line = line.strip
      return false if line.empty?
      if line.starts_with?('/')
        line.starts_with?(CRails.root) &&
          !line[(CRails.root.size + 1)..].to_s.starts_with?("lib/")
      else
        !line.starts_with?("lib/")
      end
    end

    # "Parameters" card: what the controller saw — route params (route
    # re-matched here; the Dispatcher's own match is not reachable from
    # the middleware), controller#/action, query params and body params.
    private def self.params_card(context : HTTP::Server::Context,
                                 params : Array({String, String})) : String
      String.build do |io|
        io << %(<div class="card"><h2>Parameters</h2>)
        if params.empty?
          io << "<p class=\"root\" style=\"margin:0\">None</p>"
        else
          io << "<table><tbody>"
          params.each do |key, value|
            io << "<tr><td><code>" << HTML.escape(key) << "</code></td><td><code>"
            io << HTML.escape(value) << "</code></td></tr>"
          end
          io << "</tbody></table>"
        end
        io << %(</div>)
      end
    end

    # Raw request body (peeked and re-fed, so nothing downstream breaks).
    private def self.body_card(context : HTTP::Server::Context, raw_body : String) : String
      return "" if raw_body.empty?
      displayed = raw_body.size > MAX_BODY_DISPLAY
      String.build do |io|
        io << %(<div class="card"><h2>Request body <small>) \
           << HTML.escape(context.request.headers["Content-Type"]? || "unknown content type")
        io << "</small></h2><pre>" << HTML.escape(raw_body[0, MAX_BODY_DISPLAY]) << "</pre>"
        if displayed
          bytes = raw_body.bytesize - raw_body[0, MAX_BODY_DISPLAY].bytesize
          io << "<p class=\"root\" style=\"margin:8px 0 0\">… truncated, " << bytes << " more bytes</p>"
        end
        io << %(</div>)
      end
    end

    # --- param collection --------------------------------------------------

    # Route params + controller/action + query params + body params, in
    # that order (controller/action first, like the Rails params dump).
    private def self.request_params(context : HTTP::Server::Context,
                                    app : CRails::Application?) : Array({String, String})
      params = [] of {String, String}
      if app && (match = app.routes.match(context.request.method, context.request.path))
        params << {"controller", match.route.controller}
        params << {"action", match.route.action}
        match.params.each { |key, value| params << {key, value} }
      end
      begin
        context.request.query_params.each { |key, value| params << {key, value} }
      rescue ex
      end
      body_params(context).each { |pair| params << pair }
      params
    end

    # Body params — mirrors the controller's own __merge_body_params
    # parsing: form-urlencoded pairs (incl. `post[title]` keys) and
    # top-level JSON keys; the raw body is shown by body_card as-is.
    private def self.body_params(context : HTTP::Server::Context) : Array({String, String})
      raw = peek_body(context)
      return [] of {String, String} if raw.empty?
      ctype = context.request.headers["Content-Type"]? || ""
      pairs = [] of {String, String}
      if ctype.starts_with?("application/x-www-form-urlencoded")
        begin
          HTTP::Params.parse(raw).each { |key, value| pairs << {key, value} }
        rescue ex
        end
      elsif ctype.starts_with?("application/json") || ctype.starts_with?("text/json")
        begin
          if hash = JSON.parse(raw).as_h?
            hash.each { |key, value| pairs << {key, value.to_json} }
          end
        rescue ex
        end
      end
      pairs
    end

    # Reads the request body fully and re-feeds it (the established
    # peek-and-refeed pattern — see Middleware::Dispatcher#request_method
    # and ActionController::Base#__merge_body_params). Rewind first: the
    # controller's form parsing reads the body without re-feeding it, so
    # the IO is left at EOF by the time an exception bubbles up here.
    private def self.peek_body(context : HTTP::Server::Context) : String
      body = context.request.body
      return "" unless body
      begin
        body.rewind
      rescue ex
      end
      raw = body.gets_to_end
      context.request.body = IO::Memory.new(raw)
      raw
    end
  end
end
