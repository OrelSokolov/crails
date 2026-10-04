require "log"
require "http"
require "action_pack_cr"
require "./observability"
require "./otel"

# CRails — the `Rails` module equivalent (the `CRails` namespace is the
# only intentional 1:1 difference, see ../PLAN.md).
module CRails
  VERSION = "0.1.0"

  enum Env
    Development
    Test
    Production

    def development? : Bool
      self == Development
    end

    def test? : Bool
      self == Test
    end

    def production? : Bool
      self == Production
    end
  end

  @@application : Application?
  @@env : Env?
  @@root : String?
  @@logger : Log?

  def self.application : Application
    @@application.not_nil!
  end

  def self.application=(app : Application) : Application
    @@application = app
  end

  def self.env : Env
    @@env ||= begin
      raw = (ENV["CRAILS_ENV"]? || ENV["RAILS_ENV"]? || "development").downcase.tr("-", "_")
      Env.parse?(raw) || Env::Development
    end
  end

  def self.root : String
    @@root ||= ENV["CRAILS_ROOT"]? || Dir.current
  end

  def self.logger : Log
    # The default root binding (stderr, info) is used; no extra binding
    # or messages get logged twice.
    @@logger ||= Log.for("crails")
  end

  class Config
    property host : String = "localhost"
    property port : Int32 = 3000
    # JSON request logs: CRails extension (Rails 8 ships no JSON log
    # formatter); on by default in production like Rails' JSON-ish prod
    # logging posture, text lines elsewhere. CRAILS_LOG_JSON=1 forces
    # JSON in any env (ops/bench knob).
    def initialize
      @log_json = CRails.env.production? || ENV["CRAILS_LOG_JSON"]? == "1"
    end

    property log_json : Bool
    property? metrics : Bool = true
  end

  class Application
    getter routes : CRails::Routes::RouteSet
    getter config : CRails::Config
    getter? initialized = false

    def initialize
      @routes = CRails::Routes::RouteSet.new
      @config = CRails::Config.new
    end

    def initialize! : self
      @initialized = true
      self
    end

    # HTTP entry point: routing + dispatch + logging + error pages.
    def call(context : HTTP::Server::Context) : Nil
      rid = Observability.request_id(context)
      context.response.headers[Observability::REQUEST_ID_HEADER] = rid
      started = Time.instant
      status = 200
      unless config.log_json
        CRails.logger.info { Observability.log_started(rid, context) }
      end
      begin
        unless Observability.builtin?(context, routes, rid, config.log_json)
          dispatch(context, rid)
        end
        status = context.response.status.code
      rescue ex : ActionController::RoutingError
        context.response.status_code = 404
        context.response.headers["Content-Type"] = "text/html; charset=UTF-8"
        context.response.print NOT_FOUND_PAGE
        status = 404
      rescue ex : ActionController::TooManyRequests
        CRails.logger.warn { "#{context.request.method} #{context.request.path} rate limited (429)" }
        context.response.status_code = 429
        context.response.headers["Content-Type"] = "text/html; charset=utf-8"
        status = 429
      rescue ex : Exception
        CRails.logger.error(exception: ex) { "#{context.request.method} #{context.request.path} failed" }
        context.response.status_code = 500
        context.response.headers["Content-Type"] = "text/plain; charset=utf-8"
        body = "500 Internal Server Error"
        body += "\n#{ex}\n#{ex.backtrace?.try(&.join('\n'))}" if CRails.env.development?
        context.response.print body
        status = 500
      ensure
        elapsed = Time.instant - started
        duration_ms = elapsed.total_milliseconds
        context.response.headers["X-Runtime"] = elapsed.total_seconds.to_s
        Observability::METRICS.observe(context.request.method, status, elapsed.total_seconds)
        OTel.record_http_span(rid, context.request.method, context.request.path, status, elapsed.total_seconds)
        if config.log_json
          CRails.logger.info { Observability.log_json_entry(rid, context, status, duration_ms) }
        else
          CRails.logger.info { Observability.log_completed(rid, status, duration_ms) }
        end
      end
    end

    private def dispatch(context : HTTP::Server::Context, rid : String? = nil) : Nil
      match = routes.match(context.request.method, context.request.path)
      unless match
        raise ActionController::RoutingError.new(
          "No route matches #{context.request.method} #{context.request.path}")
      end
      klass = ActionController::Dispatch.resolve(match.route.controller)
      unless klass
        raise ActionController::RoutingError.new(
          "Unknown controller '#{match.route.controller}' (not registered at compile time)")
      end
      if rid && !config.log_json
        CRails.logger.info { Observability.log_processing(rid, match.route.controller, match.route.action, nil) }
      end
      controller = klass.new(context)
      controller.__set_params(match.params)
      controller.__run_action(match.route.action)
    end

    NOT_FOUND_PAGE = "<!doctype html><html><body><h1>404 Not Found</h1></body></html>"

    # --- built-in server binary commands (bin/app serve|routes|bot:poll) ---

    def boot(argv : Array(String)) : Nil
      case argv[0]? || "serve"
      when "serve" then serve(argv.skip(1)) # skip(1), not [1..]: [][1..] raises
      when "routes" then print_routes
      when "bot:poll"
        platform = argv[1]? || "telegram"
        if poller = bot_poller
          STDERR.puts "ActionBot: polling #{platform} (Ctrl-C to stop)"
          poller.call(platform)
        else
          STDERR.puts "No bots compiled in (app/bots/** defines them; " \
                      "crails generate bot adds the wiring)"
          exit 1
        end
      else
        STDERR.puts "Usage: app [serve] [routes] [bot:poll PLATFORM] [-p PORT] [-b HOST]"
        exit 1
      end
    end

    # Set by the app's app/bots/** glue (`bin/app bot:poll telegram`);
    # keeps railties free of an action_bot dependency.
    property bot_poller : Proc(String, Nil)? = nil

    private def serve(args : Array(String)) : Nil
      port = config.port
      host = config.host
      i = 0
      while i < args.size
        case args[i]
        when "-p", "--port" then port = args[i + 1].to_i; i += 2
        when "-b", "--bind" then host = args[i + 1]; i += 2
        when "-e", "--env"  then i += 2 # env already comes via CRAILS_ENV
        else
          STDERR.puts "Unknown option: #{args[i]}"
          exit 1
        end
      end
      server = HTTP::Server.new do |context|
        CRails.application.call(context)
      end
      reuse_port = ENV["CRAILS_REUSE_PORT"]? == "1"
      address = server.bind_tcp(host, port, reuse_port: reuse_port)
      write_pidfile
      # Graceful shutdown: stop accepting, let in-flight requests
      # finish, exit 0. With CRAILS_REUSE_PORT=1 a replacement process
      # binds the same port first, giving zero-downtime restarts.
      shutdown = ->(signal : Signal) do
        CRails.logger.info { "SIG#{signal} received, shutting down gracefully" }
        spawn do
          server.close
          # Give in-flight requests a moment to drain, then exit.
          sleep 2.seconds
          exit 0
        end
      end
      Signal::INT.trap { shutdown.call(Signal::INT) }
      Signal::TERM.trap { shutdown.call(Signal::TERM) }
      CRails.logger.info { "CRails #{VERSION} (#{CRails.env}) listening on http://#{address}#{" (reuse_port)" if reuse_port}" }
      server.listen
      # server.listen returns once the server is closed: drain is done.
      CRails.logger.info { "server drained, bye" }
      delete_pidfile
    end

    private def write_pidfile : Nil
      dir = File.join(CRails.root, "tmp", "pids")
      Dir.mkdir_p(dir)
      File.write(File.join(dir, "app.pid"), Process.pid.to_s)
    rescue File::Error
      # read-only FS or missing tmp/: pidfile is best-effort
    end

    private def delete_pidfile : Nil
      File.delete(File.join(CRails.root, "tmp", "pids", "app.pid"))
    rescue File::Error
    end

    def print_routes : Nil
      printf("%-12s %-7s %-24s %s\n", "Prefix", "Verb", "URI Pattern", "Controller#Action")
      routes.routes.each do |route|
        printf("%-12s %-7s %-24s %s#%s\n",
          route.name || "", route.verb, route.pattern, route.controller, route.action)
      end
    end
  end
end
