# ActionController::Base — Iteration 0 slice.
#
# Codegen strategy (no runtime metaprogramming):
# - `macro inherited` registers each controller subclass (TypeNode) in
#   ActionController::REGISTRY at compile time.
# - A top-level `macro finished` hook runs at the end of the program and
#   injects `__run_action` / `__render_view` into every concrete
#   controller, wiring actions to ECR templates via `ECR.embed`.
#
# Views root is taken from CRAILS_VIEWS (compile-time ENV), so specs and
# apps can point it at their own `app/views`. Default: "app/views",
# relative to the directory `crystal build` runs in.

module ActionController
  VERSION = "0.1.0"

  # Compile-time registry of controller classes (filled by `inherited`).
  REGISTRY = [] of TypeNode
  # Compile-time registry of before_action filters / rescue handlers
  # (filled by the `before_action` / `rescue_from` macros).
  FILTERS = [] of {TypeNode, Symbol, NamedTuple}
  RESCUERS = [] of {TypeNode, TypeNode, Symbol}

  class RoutingError < Exception
  end

  class Base
    include ActionView::Helpers

    getter context : HTTP::Server::Context
    getter params : Parameters

    def initialize(@context : HTTP::Server::Context)
      @params = Parameters.new
      @performed = false
    end

    def request : HTTP::Request
      @context.request
    end

    def response : HTTP::Server::Response
      @context.response
    end

    @cookies : Cookies?
    @session : Session?
    @flash : Flash?

    def cookies : Cookies
      @cookies ||= Cookies.new(@context)
    end

    def session : Session
      @session ||= Session.new(cookies)
    end

    def flash : Flash
      @flash ||= Flash.new(cookies)
    end

    # --- filters ------------------------------------------------------

    # before_action :authenticate, only: [:index] / except: / if: / unless:
    macro before_action(*names, **opts)
      {% for name in names %}
        {% ActionController::FILTERS << { @type, name, opts } %}
      {% end %}
    end

    macro skip_before_action(*names, **opts)
      {% for name in names %}
        {% ActionController::FILTERS << { @type, :"__skip_#{name}", opts } %}
      {% end %}
    end

    macro rescue_from(exception, **opts)
      {% handler = opts[:with] || opts["with"] %}
      {% raise "rescue_from needs a `with:` handler" unless handler %}
      {% ActionController::RESCUERS << { @type, exception, handler } %}
    end

    # --- explicit rendering ---

    def render(json : String, status = 200) : Nil
      @performed = true
      response.status_code = status_code(status)
      response.headers["Content-Type"] = "application/json; charset=utf-8"
      response.print json
    end

    def render(plain : String? = nil, html : String? = nil, status = 200, content_type : String? = nil) : Nil
      @performed = true
      response.status_code = status_code(status)
      if body = plain
        response.headers["Content-Type"] = content_type || "text/plain; charset=utf-8"
        response.print body
      elsif body = html
        response.headers["Content-Type"] = content_type || "text/html; charset=utf-8"
        response.print body
      else
        raise ArgumentError.new("render needs plain: or html:")
      end
    end

    def head(status) : Nil
      @performed = true
      response.status_code = status_code(status)
    end

    # --- redirection ---------------------------------------------------

    def redirect_to(location : String, status = 302, notice : String? = nil,
                    alert : String? = nil) : Nil
      flash["notice"] = notice if notice
      flash["alert"] = alert if alert
      @performed = true
      response.status_code = status_code(status)
      response.headers["Location"] = location
      # любой Rails-ответ несёт Content-Type; редирект — text/html
      response.headers["Content-Type"] ||= "text/html; charset=utf-8"
    end

    def redirect_back(fallback_location : String, status = 302) : Nil
      location = request.headers["Referer"]? || fallback_location
      redirect_to(location, status)
    end

    # --- respond_to ----------------------------------------------------

    def respond_to(& : RespondToCollector ->) : Nil
      yield RespondToCollector.new(__request_format)
    end

    class RespondToCollector
      def initialize(@format : String)
      end

      def html(&) : Nil
        yield if @format == "html"
      end

      def json(&) : Nil
        yield if @format == "json"
      end

      # format.turbo_stream без блока — не-op: дефолтный рендер после
      # экшена сам отрендерит #{action}.turbo_stream.erb (см.
      # __default_render), как implicit render в Rails. С блоком —
      # исполняет блок (как html/json).
      def turbo_stream(&) : Nil
        return unless @format == "turbo_stream"
        yield
      end

      def turbo_stream : Nil
      end

      def any(&) : Nil
        yield
      end
    end

    # html unless ?format=json / .json / Accept: application/json;
    # turbo_stream по ?format= / Accept: text/vnd.turbo-stream.html
    private def __request_format : String
      if (fmt = params[:format]?.try(&.to_s)) && {"json", "turbo_stream"}.includes?(fmt)
        return fmt
      end
      if request.headers["Accept"]?.try(&.includes?("text/vnd.turbo-stream.html"))
        return "turbo_stream"
      end
      if request.headers["Accept"]?.try(&.includes?("application/json"))
        return "json"
      end
      "html"
    end

    private def status_code(status : Int32 | Symbol) : Int32
      case status
      when Int32                then status
      when :ok                  then 200
      when :created             then 201
      when :no_content          then 204
      when :moved_permanently   then 301
      when :found               then 302
      when :not_modified        then 304
      when :bad_request         then 400
      when :unauthorized        then 401
      when :forbidden           then 403
      when :not_found           then 404
      when :unprocessable_content then 422
      when :internal_server_error then 500
      else
        raise ArgumentError.new("unsupported status symbol: #{status}")
      end
    end

    # --- internal machinery (generated/driver code) ---

    def __set_params(route_params : Hash(String, String)) : Nil
      raw = {} of String => Parameters::Value
      route_params.each { |k, v| raw[k] = v }
      query = URI::Params.parse(request.query || "")
      query.each do |key, value|
        raw[key] = value
      end
      __merge_body_params(raw)
      @params = Parameters.from(raw)
    end

    private def __merge_body_params(raw : Hash(String, Parameters::Value)) : Nil
      case request.headers["Content-Type"]?
      when .nil? then nil
      when /json/
        body = request.body.try(&.gets_to_end) || ""
        return if body.empty?
        if (json = JSON.parse(body).as_h?)
          json.each do |k, v|
            raw_val = v.raw
            raw[k] = case raw_val
            when String then raw_val
            when Int32  then raw_val
            when Int64  then raw_val
            when Float64 then raw_val
            when Bool   then raw_val
            when Nil    then raw_val
            when Array  then raw_val.map { |e| (e.as?(String) || e.to_s).as(Parameters::Scalar) }
            when Hash   then Parameters.from(raw_val)
            else             v.to_s
            end
          end
        end
      when /form-urlencoded/
        body = request.body.try(&.gets_to_end) || ""
        URI::Params.parse(body).each do |k, v|
          if k.includes?('[') && k.ends_with?(']') && (eq = k.index('['))
            # nested form keys: post[title]=x -> {"post" => {"title" => "x"}}
            name = k[0...eq]
            inner_key = k[(eq + 1)...(k.size - 1)]
            sub = raw[name]?
            unless sub.is_a?(Parameters)
              sub = Parameters.new
              raw[name] = sub
            end
            sub.as(Parameters)[inner_key] = v
          else
            raw[k] = v
          end
        end
      end
    end

    # Overwritten by codegen in concrete controllers.
    def __run_action(action : String) : Nil
      raise RoutingError.new("no actions generated for #{self.class} (is it abstract?)")
    end

    # Overwritten by codegen in concrete controllers.
    def __render_view(action : String) : String
      raise RoutingError.new("no templates generated for #{self.class}")
    end

    def __default_render(action : String) : Nil
      @performed = true
      if __request_format == "turbo_stream"
        content = __render_view(action, "turbo_stream").to_s
        response.headers["Content-Type"] = "text/vnd.turbo-stream.html; charset=utf-8"
        response.print content
      else
        content = __render_view(action)
        body = __layout? ? __render_layout { content.to_s } : content.to_s
        response.headers["Content-Type"] = "text/html; charset=utf-8"
        response.print body
      end
    end

    def __layout? : Bool
      {{ (`(test -f #{env("CRAILS_VIEWS") || "app/views"}/layouts/application.html.erb && echo yes) || true`) != "" }}
    end

    macro inherited
      {% ActionController::REGISTRY << @type %}
    end
  end
end

# End-of-program codegen: runs after every controller class is defined.
macro finished
  {% for t in ActionController::REGISTRY %}
    {% unless t.abstract? %}
      {% parts = t.name.split("::") %}
      {% dir = parts.last.underscore.gsub(/_controller$/, "") %}
      {% if parts.size > 1 %}
        {% dir = parts[0...-1].map(&.underscore).join("/") + "/" + dir %}
      {% end %}
      {% root = env("CRAILS_VIEWS") || "app/views" %}

      class ::{{ t.stringify.id }}
        # Dispatch a routed action: run it, then default-render its
        # template inside the layout unless the action already rendered.
        def __run_action_dispatch(action : String) : Nil
          __run_before_filters(action)
          return if @performed
          case action
          {% for m in t.methods %}
            {% is_action = m.args.empty? && !m.name.stringify.starts_with?("__") && m.name.stringify != m.name.stringify.capitalize %}
            {% if is_action %}
          when {{ m.name.stringify }}
            {{ m.name.id }}
            __default_render({{ m.name.stringify }}) unless @performed
            {% end %}
          {% end %}
          else
            raise ::ActionController::RoutingError.new(
              "Unknown action #{action} for #{self.class}")
          end
        end

        # Registered before_action filters for this controller (its own
        # and inherited ones, minus skip_before_action'd names).
        def __run_before_filters(action : String) : Nil
          {% applicable = [] of NamedTuple %}
          {% for f in ActionController::FILTERS %}
            {% if f[0] == t || t.ancestors.includes?(f[0]) %}
              {% unless f[1].stringify.starts_with?("__skip_") %}
                {% skipped = false %}
                {% for s in ActionController::FILTERS %}
                  {% if (s[0] == t || t.ancestors.includes?(s[0])) && s[1].stringify.starts_with?("__skip_") %}
                    {% if s[1].stringify[7..] == f[1].stringify %}
                      {% skipped = true %}
                    {% end %}
                  {% end %}
                {% end %}
                {% applicable << {name: f[1], opts: f[2]} unless skipped %}
              {% end %}
            {% end %}
          {% end %}
          {% for f in applicable %}
            {% opts = f[:opts] %}
            {% cond = "true" %}
            {% if only = opts[:only] %}
              {% cond = "[" + only.map { |a| "\"" + a.stringify.gsub(/^:/, "") + "\"" }.join(", ") + "].includes?(action)" %}
            {% end %}
            {% if except = opts[:except] %}
              {% cond = cond + " && ![" + except.map { |a| "\"" + a.stringify.gsub(/^:/, "") + "\"" }.join(", ") + "].includes?(action)" %}
            {% end %}
            {% if c = opts[:if] %}
              {% cond = cond + " && " + c.stringify %}
            {% end %}
            {% if c = opts[:unless] %}
              {% cond = cond + " && !(" + c.stringify + ")" %}
            {% end %}
            if {{ cond.id }}
              {{ f[:name].id }}
              return if @performed
            end
          {% end %}
          nil
        end

        # rescue_from handlers for this controller (own + inherited).
        {% rescue_clauses = [] of String %}
        {% for r in ActionController::RESCUERS %}
          {% if r[0] == t || t.ancestors.includes?(r[0]) %}
            {% rescue_clauses << "rescue ex : " + r[1].stringify + "\n  " + r[2].stringify[1..] + "(ex)" %}
          {% end %}
        {% end %}
        {% unless rescue_clauses.empty? %}
          def __rescue_with_handlers(&) : Nil
            begin
              yield
            {% for clause in rescue_clauses %}
              {{ clause.id }}
            {% end %}
            end
          end

          def __run_action(action : String) : Nil
            __rescue_with_handlers { __run_action_dispatch(action) }
          end
        {% else %}
          def __run_action(action : String) : Nil
            __run_action_dispatch(action)
          end
        {% end %}

        # Render the action's ERB template with the controller as
        # context (instance variables, `params`, helpers are visible).
        # `format` = "html" (default) or "turbo_stream".
        def __render_view(action : String, format : String = "html") : ::ActionView::SafeString
          if format == "turbo_stream"
            return __render_view_turbo_stream(action)
          end
          case action
          {% for m in t.methods %}
            {% is_action = m.args.empty? && !m.name.stringify.starts_with?("__") && m.name.stringify != m.name.stringify.capitalize %}
            {% if is_action %}
              {% path = root + "/" + dir + "/" + m.name.stringify + ".html.erb" %}
              {% missing_msg = "Missing template " + path %}
          when {{ m.name.stringify }}
            {% if (`(test -f #{path} && echo yes) || true`) != "" %}
              __av_tpl_{{ m.name.id }}
            {% else %}
              raise ::ActionController::RoutingError.new({{ missing_msg }})
            {% end %}
            {% end %}
          {% end %}
          else
            raise ::ActionController::RoutingError.new(
              "No template for #{action} (#{self.class})")
          end
        end

        # Turbo-stream формат: #{action}.turbo_stream.erb без layout.
        def __render_view_turbo_stream(action : String) : ::ActionView::SafeString
          case action
          {% for m in t.methods %}
            {% is_action = m.args.empty? && !m.name.stringify.starts_with?("__") && m.name.stringify != m.name.stringify.capitalize %}
            {% if is_action %}
              {% ts_path = root + "/" + dir + "/" + m.name.stringify + ".turbo_stream.erb" %}
          when {{ m.name.stringify }}
            {% if (`(test -f #{ts_path} && echo yes) || true`) != "" %}
              __av_ts_tpl_{{ m.name.id }}
            {% else %}
              raise ::ActionController::RoutingError.new("Missing template " + {{ ts_path }})
            {% end %}
            {% end %}
          {% end %}
          else
            raise ::ActionController::RoutingError.new(
              "No template for #{action} (#{self.class})")
          end
        end

        {% for m in t.methods %}
          {% is_action = m.args.empty? && !m.name.stringify.starts_with?("__") && m.name.stringify != m.name.stringify.capitalize %}
          {% if is_action %}
            {% path = root + "/" + dir + "/" + m.name.stringify + ".html.erb" %}
            {% if (`(test -f #{path} && echo yes) || true`) != "" %}
              compile_template "__av_tpl_{{ m.name.id }}", {{ path }}
            {% end %}
            {% ts_path = root + "/" + dir + "/" + m.name.stringify + ".turbo_stream.erb" %}
            {% if (`(test -f #{ts_path} && echo yes) || true`) != "" %}
              compile_template "__av_ts_tpl_{{ m.name.id }}", {{ ts_path }}
            {% end %}
          {% end %}
        {% end %}

        {% layout_path = root + "/layouts/application.html.erb" %}
        {% if (`(test -f #{layout_path} && echo yes) || true`) != "" %}
          compile_layout "__av_layout", {{ layout_path }}

          def __render_layout(& : -> String) : String
            __av_layout { yield }.to_s
          end
        {% else %}
          def __render_layout(& : -> String) : String
            yield
          end
        {% end %}
      end
    {% end %}
  {% end %}

  # Resolve a route's controller name ("welcome", "admin/posts") to the
  # compile-time-registered controller class.
  module ActionController
    module Dispatch
      def self.resolve(controller_name : String)
        case controller_name
        {% for t in ActionController::REGISTRY %}
          {% unless t.abstract? %}
            {% parts = t.name.split("::") %}
            {% key = parts.last.underscore.gsub(/_controller$/, "") %}
            {% if parts.size > 1 %}
              {% key = parts[0...-1].map(&.underscore).join("/") + "/" + key %}
            {% end %}
        when {{ key }} then {{ t.stringify.id }}
          {% end %}
        {% end %}
        else
          nil
        end
      end
    end
  end
end
