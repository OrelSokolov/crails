# CRails monorepo build.
#
#   rake            # build everything (default): shard deps, crails CLI,
#                   # shard binaries, demo app server binary
#   rake build:cli  # railties.cr/bin/crails only
#   rake build:app  # hello_world/hello/bin/app only
#   rake spec       # all shard test suites
#
# Run the app:  ./bin/server   |  ./bin/console

ROOT = File.expand_path(__dir__)
APP  = File.join(ROOT, "hello_world", "hello")

SHARDS = %w[
  active_support.cr
  action_view.cr
  action_pack.cr
  active_record.cr
  active_agent.cr
  active_backup.cr
  action_bot.cr
  kiq.cr
  railties.cr
]

task default: :build

desc "Build everything: deps, crails CLI, shard binaries, demo app"
task build: %i[deps build:cli build:app build:kiq]

desc "Install shard dependencies (idempotent)"
task :deps do
  SHARDS.each do |shard|
    Dir.chdir(File.join(ROOT, shard)) do
      next unless File.exist?("shard.yml")
      sh "shards install" do |ok, _res|
        raise "shards install failed in #{shard}" unless ok || Dir.exist?("lib")
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

desc "Build the demo app server (hello_world/hello/bin/app)"
task :"build:app" do
  Dir.chdir(APP) do
    sh "crystal build src/app.cr -o bin/app"
  end
end

desc "Build the kiq worker CLI (kiq.cr/bin/kiq)"
task :"build:kiq" do
  Dir.chdir(File.join(ROOT, "kiq.cr")) do
    sh "shards build kiq"
  end
end

desc "Run all shard test suites"
task :spec do
  SHARDS.each do |shard|
    Dir.chdir(File.join(ROOT, shard)) do
      puts "==> #{shard}"
      if shard == "action_pack.cr"
        sh "make spec"
      elsif shard == "active_record.cr"
        sh "crystal spec"
        # SQLite adapter oracle suite: own compile-time schema fixture
        # (CRAILS_SCHEMA is per-compilation; PG suites use db/schema.yml)
        sh({"CRAILS_SCHEMA" => "spec/fixtures/sqlite_schema.yml"},
           "crystal spec spec/sqlite_oracle_spec.cr")
      else
        sh "crystal spec"
      end
    end
  end
end
