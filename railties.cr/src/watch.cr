# `crails watch` — the transactional dev loop.
#
# The server never goes down for a build's duration: a change builds
# to a temporary binary while the old process keeps serving, and the
# swap is a commit transaction:
#
#   BUILD     crystal build -o bin/.app.next (the old server keeps
#             running). Edits arriving mid-build do NOT kill the
#             compiler — killing on every mid-build edit livelocks a
#             long Crystal build against an active editor; they
#             coalesce into the next chained build instead.
#   RE-CHECK  a stat scan against the build's start time: the
#             filesystem, not the event queue, is the source of
#             truth. Changed under the compiler → chain: build again.
#   COMMIT    rename(.app.next → bin/app) — atomic, and the running
#             process holds the old inode (building straight to
#             bin/app could SIGBUS it); TERM the old server and wait
#             for the exit (the port is guaranteed free); exec the
#             new binary.
#   VERIFY    the new server must survive BOOT_GRACE. A boot crash
#             (compile-clean but an initializer raises) rolls back to
#             bin/.app.lkg — the last known good binary — so one
#             broken iteration never kills the dev loop.
#
# Events come from ProjectWatch (fswatch): gitignore/hidden subtrees
# never reach the kernel watch tables, the storm of one logical edit
# arrives as one batch, and the app's `lib/` symlinks are watched
# through their real checkouts (inotify does not follow symlinks).
# Events are only a HINT — every gate and re-check re-stats the
# world, so a lost or overflowed event queue cannot desync the loop.

require "project_watch"
require "./build"
require "./changes_checker"

module CRails
  module CLI
    module Watch
      def self.run(args : Array(String)) : Nil
        Session.new.run(args)
      end

      # The loop's mutable state (the running server, the watcher) —
      # a class so signal handlers can reach both.
      class Session
        BIN      = "bin/app"
        NEXT_BIN = "bin/.app.next"
        LKG_BIN  = "bin/.app.lkg"

        QUIET      = 500.milliseconds # ProjectWatch batch window
        BOOT_GRACE = 3.seconds        # a boot crash must surface here

        @app_args = ["serve"]
        @release = false
        @roots = [] of String # app root + extra watch roots
        @server : Process?
        @watcher : ProjectWatch::Watcher?

        def run(args : Array(String)) : Nil
          port : String? = nil
          host : String? = nil
          env = "development"
          i = 0
          while i < args.size
            case args[i]
            when "-p", "--port" then port = args[i + 1]; i += 2
            when "-b", "--bind" then host = args[i + 1]; i += 2
            when "-e", "--env"  then env = args[i + 1]; i += 2
            else
              abort "ERROR: unknown option #{args[i]}"
            end
          end
          ENV["CRAILS_ENV"] = env
          @release = env == "production"
          @app_args << "-p" << port if port
          @app_args << "-b" << host if host

          Build.ensure_app
          # Initial build: no server is running yet, so building
          # straight to bin/app in place is safe (the SIGBUS concern
          # only exists while an old process maps the binary).
          Build.build_if_needed(@release) || abort("ERROR: build failed")

          @roots = [File.expand_path(Dir.current)] + extra_roots
          @server = start_server
          trap_signals

          batches = Channel(ProjectWatch::Batch).new
          @watcher = ProjectWatch.watch(Dir.current, extra_roots: @roots[1..],
                                        quiet: QUIET) do |batch|
            # The main fiber may be busy building; ProjectWatch keeps
            # coalescing meanwhile, and the commit re-check makes any
            # dropped event harmless.
            batches.send(batch) rescue Channel::ClosedError
          end

          loop do
            batch = batches.receive?
            break unless batch
            next unless batch.overflow? || relevant?(batch)
            # The authoritative gate: events woke us, stat decides.
            next unless ChangesChecker.changed?
            rebuild_cycle
          end
        end

        # --- the transaction ---------------------------------------------

        # One rebuild iteration; chains while sources keep changing
        # under the compiler. Returns with the server running the new
        # binary (commit verified) — or the OLD one if a build failed
        # or the new binary could not boot.
        private def rebuild_cycle : Nil
          loop do
            started = Time.local
            puts "==> building #{NEXT_BIN} (server keeps running)"
            return unless build_next # failed: the old server keeps
            #                        serving; the next batch retries
            if ChangesChecker.changed_since?(started)
              puts "    sources changed during the build — chaining"
              next
            end
            commit
            return
          end
        end

        private def build_next : Bool
          args = ["build", "src/app.cr", "-o", NEXT_BIN]
          args << "--release" if @release
          started = Time.instant
          ok = system("crystal", args)
          if ok
            elapsed = (Time.instant - started).total_seconds.round(2)
            puts "    compiled in #{elapsed}s"
          else
            puts "    build FAILED — the old server keeps running"
            File.delete(NEXT_BIN) if File.exists?(NEXT_BIN)
          end
          ok
        end

        # The swap: preserve the running binary as the rollback
        # target, move the new one in, restart. Only called with a
        # finished NEXT_BIN and no build in flight.
        private def commit : Nil
          File.rename(BIN, LKG_BIN)
          File.rename(NEXT_BIN, BIN)
          stop_server
          @server = start_server
          return if booted?

          puts "    new binary failed to boot — rolling back to #{LKG_BIN}"
          File.delete(BIN) # the broken one; NEXT_BIN is rewritten anyway
          File.rename(LKG_BIN, BIN)
          stop_server
          @server = start_server
          puts "    rollback failed — fix and save; the next build retries" unless booted?
        end

        # The new server process must survive BOOT_GRACE; boot crashes
        # (a migration error, an initializer raise) surface here.
        private def booted? : Bool
          deadline = Time.local + BOOT_GRACE
          while Time.local < deadline
            return false if (proc = @server) && proc.terminated?
            sleep 0.1.seconds
          end
          true
        end

        # --- server lifecycle --------------------------------------------

        private def start_server : Process?
          Process.new(BIN, @app_args, output: STDOUT, error: STDERR)
        rescue e : Exception
          puts "    failed to start bin/app: #{e.message}"
          nil
        end

        private def stop_server : Nil
          if (proc = @server)
            begin
              proc.terminate
            rescue Exception
            end
            proc.wait if proc.exists?
          end
          @server = nil
        end

        private def trap_signals : Nil
          Signal::INT.trap { shutdown }
          Signal::TERM.trap { shutdown }
          Signal::QUIT.trap { shutdown }
        end

        private def shutdown : Nil
          stop_server
          @watcher.try(&.stop)
          exit 0
        end

        # --- event classification ----------------------------------------

        # Whether a batch touches anything that feeds the binary.
        # Parity with ChangesChecker::SOURCE_GLOBS (both the gate and
        # the commit re-check stat exactly these trees): app/config/
        # src code and the shard manifests.
        private def relevant?(batch : ProjectWatch::Batch) : Bool
          batch.paths.any? do |path|
            rel_to_roots(path).try { |rel| source?(rel) }
          end
        end

        private def rel_to_roots(path : String) : String?
          @roots.each do |root|
            rel = Path[path].relative_to(root).to_s
            return rel unless rel.starts_with?("..")
          end
          nil
        end

        private def source?(rel : String) : Bool
          return true if {"shard.yml", "shard.lock"}.includes?(rel)
          {"src", "config", "app"}.any? { |dir| rel.starts_with?("#{dir}/") } &&
            (rel.ends_with?(".cr") || rel.ends_with?(".erb"))
        end

        # The app's lib/ holds symlinked shards (monorepo layout), and
        # inotify does not follow symlinks — watch each child through
        # its realpath. Real directories are watched directly (they
        # may be gitignored in the app, which would keep them out of
        # the root watch). Overlap with the root watch is harmless:
        # batches deduplicate by path.
        private def extra_roots : Array(String)
          roots = [] of String
          return roots unless Dir.exists?("lib")
          Dir.each_child("lib") do |name|
            path = File.expand_path(File.join("lib", name))
            info = File.info?(path, follow_symlinks: true)
            next unless info.try(&.type.directory?)
            roots << (File.realpath(path) rescue path)
          rescue File::Error | File::AccessDeniedError
          end
          roots
        end
      end
    end
  end
end
