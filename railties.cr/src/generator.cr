require "file_utils"

module CRails
  module Generators
    # `crails new APP_PATH` — generates the Iteration 0 app skeleton.
    class App
      def self.run(path : String) : Nil
        new(path).run
      end

      def initialize(@path : String)
        @name = File.basename(File.expand_path(@path))
      end

      def run : Nil
        dir = File.expand_path(@path)
        abort "ERROR: #{dir} already exists" if File.exists?(dir)

        exe = Process.executable_path || abort("ERROR: cannot locate the crails binary")
        railties_dir = File.dirname(File.dirname(exe)) # railties.cr/
        repo_root = File.dirname(railties_dir)          # monorepo root
        rel = Path[repo_root].relative_to?(Path[dir]) ||
          abort("ERROR: cannot compute relative path from #{dir} to #{repo_root}")

        puts "      create  #{@path}"
        dirs = [
          "src", "config/environments", "app/controllers", "app/models",
          "app/views/layouts", "app/views/welcome", "db", "public", "bin", "lib",
        ]
        dirs.each { |d| FileUtils.mkdir_p(File.join(dir, d)) }

        # Framework shards are wired as lib/ symlinks into the monorepo
        # (dev mode): shards treats duplicate path deps across the graph
        # as ambiguous sources, so the app's shard.yml stays free of
        # framework dependencies.
        {"active_support.cr", "action_view.cr", "action_pack.cr",
         "active_record.cr", "railties.cr"}.each do |shard|
          target = File.join(dir, "lib", shard.gsub('.', "_"))
          # The symlink lives inside lib/, one level deeper than the app root.
          link_target = File.join(rel, "..", shard)
          puts "      symlink lib/#{File.basename(target)} -> #{link_target}"
          File.symlink(link_target.to_s, target)
        end

        # Transitive shard deps installed inside the framework shards'
        # own lib/ dirs (active_record.cr needs db + pg at compile time).
        {"active_record.cr/lib/db", "active_record.cr/lib/pg"}.each do |dep|
          target = File.join(dir, "lib", File.basename(dep))
          next if File.exists?(target)
          link_target = File.join(rel, "..", dep)
          puts "      symlink lib/#{File.basename(dep)} -> #{link_target}"
          File.symlink(link_target.to_s, target)
        end

        write(dir, "shard.yml", shard_yml)
        write(dir, "src/app.cr", app_cr)
        write(dir, "src/console.cr", console_cr)
        write(dir, "config/application.cr", application_cr)
        write(dir, "config/routes.cr", routes_cr)
        write(dir, "config/database.yml", database_yml)
        write(dir, "config/environments/development.cr", development_cr)
        write(dir, "config/environments/production.cr", production_cr)
        write(dir, "app/controllers/application_controller.cr", application_controller_cr)
        write(dir, "app/controllers/welcome_controller.cr", welcome_controller_cr)
        write(dir, "app/models/application_record.cr", application_record_cr)
        write(dir, "app/views/layouts/application.html.ecr", layout_ecr)
        write(dir, "app/views/welcome/index.html.ecr", index_ecr)
        write(dir, "public/.gitkeep", "")
        write(dir, ".gitignore", gitignore)
        write(dir, "README.md", readme)
        write(dir, "bin/crails", bin_crails(exe))
        File.chmod(File.join(dir, "bin/crails"), 0o755)

        puts
        puts "CRails #{CRails::VERSION} app created at #{dir}"
        puts "Next steps:"
        puts "  cd #{@path}"
        puts "  bin/crails server"
        puts "  curl http://localhost:3000/"
      end

      private def write(dir : String, name : String, content : String) : Nil
        puts "      create  #{name}"
        File.write(File.join(dir, name), content)
      end

      # --- templates ---

      private def shard_yml : String
        <<-YAML
        # Framework shards come from lib/ symlinks (see bin/crails);
        # add your own dependencies here.
        name: #{@name}
        version: 0.1.0
        crystal: ">= 1.21.0"
        YAML
      end

      private def app_cr : String
        <<-CODE
        require "railties_cr"

        require "../config/application"
        require "../app/controllers/**"
        require "../config/routes"
        require "../config/environments/development"
        require "../config/environments/production"

        CRails.application.initialize!
        CRails.application.boot(ARGV)
        CODE
      end

      private def application_cr : String
        <<-CODE
        class Application < CRails::Application
          # config.port = 3000
          # config.host = "localhost"
        end

        CRails.application = Application.new
        CODE
      end

      private def routes_cr : String
        <<-CODE
        CRails.application.routes.draw do
          root "welcome#index"
        end
        CODE
      end

      # Flat sections (no YAML anchors): establish_connection_from_yaml
      # reads adapter/host/port/username/password/database per env.
      # DATABASE_URL env var overrides this file when set (like Rails).
      private def database_yml : String
        <<-YAML
        # Picked up automatically by `crails console` (DATABASE_URL
        # overrides). host starting with "/" is a unix socket directory.
        development:
          adapter: postgresql
          host: /var/run/postgresql
          username: root
          database: #{@name}_development

        test:
          adapter: postgresql
          host: /var/run/postgresql
          username: root
          database: #{@name}_test

        production:
          adapter: postgresql
          host: /var/run/postgresql
          username: root
          database: #{@name}_production
          # for TCP + password deployments set host: db.example.com,
          # port: 5432, password: ... — or just use DATABASE_URL
        YAML
      end

      private def development_cr : String
        <<-CODE
        # Loaded when CRails.env == "development"
        if CRails.env.development?
          CRails.application.config.port = 3000
        end
        CODE
      end

      private def production_cr : String
        <<-CODE
        # Loaded when CRails.env == "production"
        if CRails.env.production?
          CRails.application.config.host = "0.0.0.0"
        end
        CODE
      end

      private def application_controller_cr : String
        <<-CODE
        abstract class ApplicationController < ActionController::Base
          # before_action and friends arrive with the full action_pack port.
        end
        CODE
      end

      private def application_record_cr : String
        <<-CODE
        # Base class for models, like Rails' ApplicationRecord.
        # Attributes are generated from db/schema.yml at compile time
        # (`crails new` leaves it absent; dump one with ar_schema_dump).
        abstract class ApplicationRecord < ActiveRecord::Base
        end
        CODE
      end

      private def console_cr : String
        <<-CODE
        # CRails console bootstrap — loads the app WITHOUT starting the
        # server; used by `crails console` (every line re-runs this file).
        require "railties_cr"
        require "active_record_cr"
        require "../config/application"
        require "../app/models/**"
        require "../app/controllers/**"
        require "../config/routes"

        if (url = ENV["DATABASE_URL"]?)
          ActiveRecord::Base.establish_connection(url)
        elsif File.exists?("config/database.yml")
          ActiveRecord::Base.establish_connection_from_yaml(
            "config/database.yml", CRails.env.to_s.downcase)
        end
        CODE
      end

      private def welcome_controller_cr : String
        <<-'CODE'
        class WelcomeController < ApplicationController
          def index
            @message = "Hello from CRails"
          end
        end
        CODE
      end

      private def layout_ecr : String
        <<-'ECR'
        <!DOCTYPE html>
        <html>
          <head>
            <meta charset="utf-8">
            <title>Hello</title>
          </head>
          <body>
            <%= yield %>
          </body>
        </html>
        ECR
      end

      private def index_ecr : String
        <<-'ECR'
        <h1><%= @message %></h1>
        <p>Served by CRails <%= CRails::VERSION %> (Crystal).</p>
        ECR
      end

      private def gitignore : String
        <<-TEXT
        /lib/
        /bin/app
        /.shards/
        TEXT
      end

      private def readme : String
        <<-MD
        # #{@name}

        Generated by `crails new` (Iteration 0: hello world, no DB).

        ```
        bin/crails server     # build + run on :3000
        bin/crails console    # rails console analog (loads app + DB, icr.cr)
        bin/crails routes     # list routes
        bin/crails watch      # rebuild on change (dev loop)
        ```

        Console queries (models in app/models, schema in db/schema.yml):
        the connection is picked up automatically from
        config/database.yml (DATABASE_URL overrides it if set).

        ```
        bin/crails c
        crails(dev)> Post.count
        crails(dev)> Post.where(published: true).order(:views).limit(3).to_a
        ```
        MD
      end

      private def bin_crails(exe : String) : String
        <<-SH
        #!/bin/sh
        # CRails dev CLI wrapper (generated; points at the crails binary).
        exec "#{exe}" "$@"
        SH
      end
    end
  end
end
