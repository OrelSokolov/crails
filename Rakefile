# CRails monorepo build.
#
#   rake            # build everything (default): shard deps, crails CLI,
#                   # demo app server binary
#   rake build:cli  # railties.cr/bin/crails only
#   rake build:app  # examples/hello_world/hello/bin/app only
#   rake spec       # shard test suites (railties)
#
# Run the app:  ./bin/server   |  ./bin/console
#
# Framework shards live in their own OrelSokolov/*.cr repos and resolve
# from GitHub tags via shard.yml; only railties.cr/ is developed here.

ROOT = File.expand_path(__dir__)
APP  = File.join(ROOT, "examples", "hello_world", "hello")

SHARDS = %w[
  railties.cr
]

task default: :build

desc "Build everything: deps, crails CLI, demo app"
task build: %i[deps build:cli build:app]

desc "Install shard dependencies (idempotent)"
task :deps do
  ([ROOT] + SHARDS.map { |s| File.join(ROOT, s) }).each do |dir|
    Dir.chdir(dir) do
      next unless File.exist?("shard.yml")
      sh "shards install" do |ok, _res|
        raise "shards install failed in #{dir}" unless ok || Dir.exist?("lib")
      end
    end
  end
end

desc "Build the crails CLI (railties.cr/bin/crails)"
task :"build:cli" do
  Dir.chdir(File.join(ROOT, "railties.cr")) do
    sh "shards build crails"
  end
end

desc "Build the demo app server (examples/hello_world/hello/bin/app)"
task :"build:app" do
  Dir.chdir(APP) do
    sh "crystal build src/app.cr -o bin/app"
  end
end

desc "Run all shard test suites"
task :spec do
  SHARDS.each do |shard|
    Dir.chdir(File.join(ROOT, shard)) do
      puts "==> #{shard}"
      sh "crystal spec"
    end
  end
end
