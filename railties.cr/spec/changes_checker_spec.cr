# ChangesChecker: bin/app mtime vs app sources and dependencies —
# `crails server`/`routes` must not recompile an up-to-date binary.

require "spec"
require "../src/changes_checker"
require "file_utils"

describe "ChangesChecker.changed?" do
  it "is stale without bin/app, fresh when the binary is newest" do
    dir = File.join(Dir.tempdir, "crails_changes_spec_#{Random::Secure.hex(4)}")
    FileUtils.mkdir_p(File.join(dir, "src"))
    FileUtils.mkdir_p(File.join(dir, "config"))
    FileUtils.mkdir_p(File.join(dir, "lib", "some_shard", "src"))

    bin_path = File.join(dir, "bin", "app")
    routes = File.join(dir, "config", "routes.cr")
    dep = File.join(dir, "lib", "some_shard", "src", "dep.cr")

    # symlinked shard (monorepo layout) with a self-referencing
    # lib/ symlink — the walker must not loop on it
    linked = File.join(dir, "vendor", "linked_shard")
    FileUtils.mkdir_p(File.join(linked, "src"))
    FileUtils.mkdir_p(File.join(linked, "lib"))
    File.write(File.join(linked, "src", "linked.cr"), "")
    File.symlink(linked, File.join(dir, "lib", "linked_shard"))
    File.symlink(linked, File.join(linked, "lib", "linked_shard"))
    linked_dep = File.join(linked, "src", "linked.cr")

    Dir.cd(dir) do
      File.write(File.join(dir, "src", "app.cr"), "")
      File.write(routes, "")
      File.write(dep, "")
      # no binary yet -> stale
      CRails::CLI::ChangesChecker.changed?.should be_true

      # binary newer than sources and lib -> fresh
      FileUtils.mkdir_p(File.join(dir, "bin"))
      File.write(bin_path, "")
      FileUtils.touch(bin_path)
      CRails::CLI::ChangesChecker.changed?.should be_false

      # app source edited after the build -> stale again
      FileUtils.touch(routes)
      CRails::CLI::ChangesChecker.changed?.should be_true

      # rebuild, then a plain lib/ dependency change -> stale
      FileUtils.touch(bin_path)
      CRails::CLI::ChangesChecker.changed?.should be_false
      FileUtils.touch(dep)
      CRails::CLI::ChangesChecker.changed?.should be_true

      # rebuild, then a change behind a symlinked shard -> stale
      FileUtils.touch(bin_path)
      CRails::CLI::ChangesChecker.changed?.should be_false
      FileUtils.touch(linked_dep)
      CRails::CLI::ChangesChecker.changed?.should be_true
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
