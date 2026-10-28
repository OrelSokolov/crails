module CRails
  module CLI
    module Build
      # App sources that bin/app is compiled from (shared with `crails watch`).
      SOURCE_GLOBS = ["src/**/*.cr", "config/**/*.cr", "app/**/*.cr",
                      "app/**/*.erb", "shard.yml"]

      def self.ensure_app : Nil
        unless File.exists?("shard.yml") && File.exists?("src/app.cr")
          abort "ERROR: not in a CRails app (no shard.yml / src/app.cr). Run from the app root."
        end
        if File.read("shard.yml").includes?("dependencies:") && !Dir.exists?("lib")
          puts "==> shards install"
          system("shards", ["install"]) || abort("ERROR: shards install failed")
        end
      end

      # Builds bin/app. Returns true on success.
      def self.build(release : Bool = false) : Bool
        args = ["build", "src/app.cr", "-o", "bin/app"]
        args << "--release" if release
        puts "==> crystal build src/app.cr -o bin/app#{" --release" if release}"
        started = Time.instant
        ok = system("crystal", args)
        if ok
          elapsed = (Time.instant - started).total_seconds.round(2)
          puts "    compiled in #{elapsed}s"
        end
        ok
      end

      # True when bin/app is missing or any app source is newer than the
      # binary (mtime check, no recompile needed otherwise).
      def self.stale? : Bool
        return true unless File.exists?("bin/app")
        bin_time = File.info("bin/app").modification_time
        SOURCE_GLOBS.each do |glob|
          Dir.glob(glob).each do |file|
            return true if File.info(file).modification_time > bin_time
          end
        end
        false
      end

      # Builds bin/app only when sources changed since the last build.
      # Returns true when the binary is already up to date.
      def self.build_if_needed(release : Bool = false) : Bool
        return true unless stale?
        build(release)
      end
    end
  end
end
