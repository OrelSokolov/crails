# CRails monorepo build.
#
#   rake            # build everything (default): shard deps, crails CLI,
#                   # demo app server binary
#   rake build:cli  # bin/crails only
#   rake build:app  # examples/hello_world/hello/bin/app only
#
# Run the app:  ./bin/server   |   ./bin/console
#
# Framework shards live in their own OrelSokolov/*.cr repos and resolve
# from GitHub tags via shard.yml; railties_cr specs run in its own
# repository checkout (github.com/OrelSokolov/railties.cr).

ROOT = File.expand_path(__dir__)
APP  = File.join(ROOT, "examples", "hello_world", "hello")

task default: :build

desc "Build everything: deps, crails CLI, demo app"
task build: %i[deps build:cli build:app]

desc "Install shard dependencies (idempotent)"
task :deps do
  Dir.chdir(ROOT) do
    sh "shards install" do |ok, _res|
      raise "shards install failed in #{ROOT}" unless ok || Dir.exist?("lib")
    end
  end
end

desc "Build the crails CLI (bin/crails)"
task :"build:cli" do
  Dir.chdir(ROOT) do
    sh "shards build crails"
  end
end

desc "Build the demo app server (examples/hello_world/hello/bin/app)"
task :"build:app" do
  Dir.chdir(APP) do
    sh "crystal build src/app.cr -o bin/app"
  end
end
