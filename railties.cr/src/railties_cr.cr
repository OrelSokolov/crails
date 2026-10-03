require "log"
require "http"
require "action_pack_cr"

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
      started = Time.instant
      status = 200
      begin
        dispatch(context)
        status = context.response.status.code
      rescue ex : ActionController::RoutingError
        context.response.status_code = 404
        context.response.headers["Content-Type"] = "text/plain; charset=utf-8"
        context.response.print "404 Not Found (#{ex.message})"
        status = 404
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
        if elapsed >= 1.millisecond
          CRails.logger.info { "#{context.request.method} #{context.request.path} -> #{status} (#{elapsed.total_milliseconds.round.to_i}ms)" }
        else
          CRails.logger.info { "#{context.request.method} #{context.request.path} -> #{status} (#{(elapsed.total_nanoseconds // 1000).to_i}µs)" }
        end
      end
    end

    private def dispatch(context : HTTP::Server::Context) : Nil
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
      controller = klass.new(context)
      controller.__set_params(match.params)
      controller.__run_action(match.route.action)
    end

    # --- built-in server binary commands (bin/app serve|routes) ---

    def boot(argv : Array(String)) : Nil
      case argv[0]? || "serve"
      when "serve" then serve(argv.skip(1)) # skip(1), not [1..]: [][1..] raises
      when "routes" then print_routes
      else
        STDERR.puts "Usage: app [serve] [routes] [-p PORT] [-b HOST]"
        exit 1
      end
    end

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
      address = server.bind_tcp(host, port)
      CRails.logger.info { "CRails #{VERSION} (#{CRails.env}) listening on http://#{address}" }
      server.listen
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
