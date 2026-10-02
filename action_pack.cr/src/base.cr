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

  class RoutingError < Exception
  end

  class Base
    include ActionView::Helpers

    getter context : HTTP::Server::Context
    getter params : Hash(String, String)

    def initialize(@context : HTTP::Server::Context)
      @params = {} of String => String
      @performed = false
    end

    def request : HTTP::Request
      @context.request
    end

    def response : HTTP::Server::Response
      @context.response
    end

    # --- explicit rendering (Iteration 0 slice) ---

    def render(plain : String? = nil, html : String? = nil, status = 200) : Nil
      @performed = true
      response.status_code = status_code(status)
      if body = plain
        response.headers["Content-Type"] = "text/plain; charset=utf-8"
        response.print body
      elsif body = html
        response.headers["Content-Type"] = "text/html; charset=utf-8"
        response.print body
      else
        raise ArgumentError.new("render needs plain: or html: (Iteration 0 slice)")
      end
    end

    def redirect_to(location : String, status = 302) : Nil
      @performed = true
      response.status_code = status_code(status)
      response.headers["Location"] = location
    end

    private def status_code(status : Int32 | Symbol) : Int32
      case status
      when Int32 then status
      when .ok?                 then 200
      when .created?            then 201
      when .no_content?         then 204
      when .moved_permanently?  then 301
      when .found?              then 302
      when .not_modified?       then 304
      when .bad_request?        then 400
      when .unauthorized?       then 401
      when .forbidden?          then 403
      when .not_found?          then 404
      when .unprocessable_content? then 422
      when .internal_server_error? then 500
      else
        raise ArgumentError.new("unsupported status symbol: #{status}")
      end
    end

    # --- internal machinery (generated/driver code) ---

    def __set_params(route_params : Hash(String, String)) : Nil
      @params.merge!(route_params)
      query = URI::Params.parse(request.query || "")
      query.each do |key, value|
        @params[key] = value
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
      content = __render_view(action)
      body = __layout? ? __render_layout { content } : content
      response.headers["Content-Type"] = "text/html; charset=utf-8"
      response.print body
    end

    def __layout? : Bool
      {{ (`(test -f #{env("CRAILS_VIEWS") || "app/views"}/layouts/application.html.ecr && echo yes) || true`) != "" }}
    end

    def __render_layout(& : -> String) : String
      io = IO::Memory.new
      ECR.embed {{ (env("CRAILS_VIEWS") || "app/views") + "/layouts/application.html.ecr" }}, "io"
      io.to_s
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
        def __run_action(action : String) : Nil
          case action
          {% for m in t.methods %}
            {% next unless m.args.empty? %}
            {% next if m.name.stringify.starts_with?("__") %}
            {% next if m.name.stringify == m.name.stringify.capitalize %}
          when {{ m.name.stringify }}
            {{ m.name.id }}
            __default_render({{ m.name.stringify }}) unless @performed
          {% end %}
          else
            raise ::ActionController::RoutingError.new(
              "Unknown action #{action} for #{self.class}")
          end
        end

        # Render the action's ECR template with the controller as context
        # (instance variables, `params`, helpers are visible).
        def __render_view(action : String) : String
          io = ::IO::Memory.new
          case action
          {% for m in t.methods %}
            {% next unless m.args.empty? %}
            {% next if m.name.stringify.starts_with?("__") %}
            {% next if m.name.stringify == m.name.stringify.capitalize %}
            {% path = root + "/" + dir + "/" + m.name.stringify + ".html.ecr" %}
            {% missing_msg = "Missing template " + path %}
          when {{ m.name.stringify }}
            {% if (`(test -f #{path} && echo yes) || true`) != "" %}
              ::ECR.embed {{ path }}, "io"
            {% else %}
              raise ::ActionController::RoutingError.new({{ missing_msg }})
            {% end %}
          {% end %}
          else
            raise ::ActionController::RoutingError.new(
              "No template for #{action} (#{self.class})")
          end
          io.to_s
        end
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
