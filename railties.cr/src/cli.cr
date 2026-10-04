require "./generator"

module CRails
  module CLI
    def self.run(argv : Array(String)) : Nil
      case argv[0]? || "help"
      when "new"       then Generators::App.run(argv[1]? || abort("Usage: crails new APP_PATH"))
      when "server", "s" then Server.run(argv[1..])
      when "console", "c" then Console.run(argv[1..])
      when "routes"    then Build.ensure_app; Build.build; run_app(["routes"])
      when "watch"     then Watch.run(argv[1..])
      when "db", .starts_with?("db:") then DB.run(argv)
      when "deploy"    then Deploy.run(argv[1..])
      when "generate", "g"
        case argv[1]?
        when "bot" then Agent.generate(argv[2..])
        else abort "Usage: crails generate bot NAME [--platform=telegram|whatsapp]"
        end
      when "bot:poll" then Agent.poll(argv[1..])
      when "version", "--version", "-v" then puts "CRails #{CRails::VERSION} (Crystal #{Crystal::VERSION})"
      when "about"     then about
      else help
      end
    end

    private def self.about : Nil
      puts <<-TEXT
      CRails     #{CRails::VERSION}
      Crystal    #{Crystal::VERSION}
      Env        #{CRails.env}
      Root       #{CRails.root}
      Iteration  0 (hello world; no DB, no sessions yet)
      TEXT
    end

    private def self.help : Nil
      puts <<-TEXT
      CRails #{CRails::VERSION} — a Rails-port MVC framework on Crystal (EXPERIMENTAL)

      Usage: crails COMMAND [ARGS]

      Commands:
        new APP_PATH   Generate a new application
        server, s      Build and run the app (-p PORT, -b HOST, -e ENV)
        console, c     Rails-console analog on icr.cr (loads app + DB)
        routes         Build (if needed) and list routes
        watch          Rebuild + restart on source changes (dev loop)
        db:migrate     Run pending migrations (db/migrate/*.cr)
        db:rollback    Roll back the last migration (STEP=n)
        db:schema:dump Refresh db/schema.cr + db/schema.yml
        db:schema:load Recreate the database from db/schema.cr
        generate bot   Embed a bot into this app: app/bots/ + webhook mount
                       (crails generate bot Support --platform=telegram|whatsapp)
        bot:poll     Build the app and run its bot poller role
                       (crails bot:poll telegram)
        deploy         Release-build + scp + migrate + zero-downtime restart
        version        Print versions
        about          Print framework info
      TEXT
    end

    private def self.run_app(args : Array(String)) : Nil
      Process.exec("bin/app", args)
    end
  end
end

require "./build"
require "./server"
require "./watch"
require "./console_cmd"
require "./db_tasks"
require "./deploy"
require "./agent_tasks"
