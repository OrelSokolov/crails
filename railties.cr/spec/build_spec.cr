# Build freshness: bin/app mtime vs app sources (`crails routes` & co
# must not recompile an up-to-date binary).

require "spec"
require "../src/build"
require "file_utils"

describe "Build.stale?" do
  it "is stale without bin/app, fresh when the binary is newest" do
    dir = File.join(Dir.tempdir, "crails_build_spec_#{Random::Secure.hex(4)}")
    FileUtils.mkdir_p(File.join(dir, "src"))
    FileUtils.mkdir_p(File.join(dir, "config"))

    old = Time.utc - 10.minutes
    bin_path = File.join(dir, "bin", "app")
    routes = File.join(dir, "config", "routes.cr")

    Dir.cd(dir) do
      File.write(File.join(dir, "src", "app.cr"), "")
      File.write(routes, "")
      # no binary yet -> stale
      CRails::CLI::Build.stale?.should be_true

      # binary newer than sources -> fresh
      FileUtils.mkdir_p(File.join(dir, "bin"))
      File.write(bin_path, "")
      FileUtils.touch(bin_path)
      CRails::CLI::Build.stale?.should be_false

      # routes edited after the build -> stale again
      FileUtils.touch(routes, old + 20.minutes)
      CRails::CLI::Build.stale?.should be_true
    end
  ensure
    FileUtils.rm_rf(dir) if dir
  end
end
