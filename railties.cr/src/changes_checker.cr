module CRails
  module CLI
    # Fast staleness check: is bin/app older than any app source or
    # dependency file? Pure stat (mtime) over the source trees — no
    # compilation. Lets `crails server`/`routes`/... skip redundant
    # rebuilds; pass --build to force one.
    module ChangesChecker
      SOURCE_GLOBS = ["src/**/*.cr", "config/**/*.cr", "app/**/*.cr",
                      "app/**/*.erb", "shard.yml", "shard.lock"]

      def self.changed?(bin : String = "bin/app") : Bool
        return true unless File.exists?(bin)
        changed_since?(File.info(bin).modification_time)
      end

      # Any watched source newer than *since*? The stat scan behind
      # both `changed?` and the watch loop's commit-time re-check:
      # the filesystem, not the event queue, is the source of truth.
      def self.changed_since?(since : Time) : Bool
        SOURCE_GLOBS.each do |glob|
          Dir.glob(glob).each do |file|
            return true if File.info(file).modification_time > since
          end
        end
        lib_changed?(since, "lib", Set(String).new)
      end

      # lib/ in dev apps is a set of symlinked shards (monorepo layout)
      # whose own lib/ symlinks point back at each other — plain
      # Dir.glob(follow_symlinks: true) loops on those, so walk manually
      # with a realpath visited-set (cycle guard).
      private def self.lib_changed?(since : Time, dir : String, visited : Set(String)) : Bool
        return false unless Dir.exists?(dir)
        Dir.each_child(dir) do |name|
          next if name.starts_with?('.') # .git & friends
          path = File.join(dir, name)
          info = File.info?(path, follow_symlinks: true)
          next unless info
          if info.directory?
            next unless visited.add?(File.realpath(path))
            return true if lib_changed?(since, path, visited)
          elsif name.ends_with?(".cr") || name == "shard.yml"
            return true if info.modification_time > since
          end
        end
        false
      end
    end
  end
end
