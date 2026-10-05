require "log"
require "http"
require "action_pack_cr"
require "./observability"
require "./middleware"
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
      # Default middleware stack (Rails 8.1 order for the pieces CRails
      # ships; the full Rails list is in oracle/middleware_expected.yml,
      # default_stack_names). Apps mutate it freely in config/*.cr via
      # use/insert_before/insert_after/swap/delete.
      @middleware = CRails::MiddlewareStack.new
      @middleware.use CRails::Middleware::RequestId
      @middleware.use CRails::Middleware::RequestLogger
      @middleware.use CRails::Middleware::ShowExceptions
      @middleware.use CRails::Middleware::Head
    end

    property log_json : Bool
    property? metrics : Bool = true
    getter middleware : CRails::MiddlewareStack
  end

  class Application
    getter routes : CRails::Routes::RouteSet
    getter config : CRails::Config
    getter? initialized = false
    @middleware_chain : HTTP::Handler?

    def initialize
      @routes = CRails::Routes::RouteSet.new
      @config = CRails::Config.new
    end

    def initialize! : self
      @initialized = true
      self
    end

    # HTTP entry point: the middleware stack (config.middleware) with
    # routing dispatch as the terminal handler.
    def call(context : HTTP::Server::Context) : Nil
      middleware_chain.call(context)
    end

    # The composed handler chain — built once, on first use. Middleware
    # added after the first request takes no effect (same as Rails:
    # config.middleware mutations happen at boot time only).
    def middleware_chain : HTTP::Handler
      @middleware_chain ||= begin
        head = config.middleware.build(Middleware::Dispatcher.new(self))
        node = head
        while node.is_a?(HTTP::Handler)
          if node.is_a?(Middleware::Configurable)
            node.application = self
          end
          node = node.next
        end
        head
      end
    end

    # --- built-in server binary commands (bin/app serve|routes|bot:poll) ---

    def boot(argv : Array(String)) : Nil
      case argv[0]? || "serve"
      when "serve" then serve(argv.skip(1)) # skip(1), not [1..]: [][1..] raises
      when "routes" then print_routes
      when "middleware" then print_middleware
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
        STDERR.puts "Usage: app [serve] [routes] [middleware] [bot:poll PLATFORM] [-p PORT] [-b HOST]"
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
      middleware_chain # compose before listening: no first-request race
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

    # `rake middleware` equivalent: the effective stack, "use NAME" per line.
    def print_middleware(io : IO = STDOUT) : Nil
      config.middleware.each { |m| io << "use " << m.name << '\n' }
    end
  end
end
