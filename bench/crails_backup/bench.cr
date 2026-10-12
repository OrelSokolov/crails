# Backup/restore throughput: seeded PostgreSQL (N rows with ~200 B
# payloads) + a file tree (M x 1 MiB) -> ActiveBackup.create /
# .restore wall times; our ustar+gzip writer vs system `tar czf`.
require "colorize"
require "active_backup_cr"

ROWS = (ARGV[0]? || "200000").to_i
FILES = (ARGV[1]? || "100").to_i
DB_NAME = "crails_backup_bench"
DB_URL = "postgres:///#{DB_NAME}?host=/var/run/postgresql"

def now : Float64
  Time.utc.to_unix_f
end

def rm_tree(path : String) : Nil
  return unless File.exists?(path)
  if File.directory?(path)
    Dir.children(path).each { |c| rm_tree(File.join(path, c)) }
    Dir.delete(path)
  else
    File.delete(path)
  end
end

def bench(label : String, &)
  t0 = now
  result = yield
  elapsed = now - t0
  puts("%-34s %8.2f s" % [label, elapsed])
  result
end

admin = DB.open("postgres:///postgres")
admin.exec("DROP DATABASE IF EXISTS #{DB_NAME}")
admin.exec("CREATE DATABASE #{DB_NAME}")

workdir = "/tmp/backup_bench"
rm_tree(workdir) if File.exists?(workdir)
Dir.mkdir_p(File.join(workdir, "storage"))
storage = File.join(workdir, "storage")

db = DB.open(DB_URL)
bench("seed #{ROWS} rows (~#{ROWS * 200 // 1_000_000} MB data)") do
  db.exec("CREATE TABLE bench_rows (id bigserial PRIMARY KEY, payload text)")
  db.exec("INSERT INTO bench_rows (payload)
           SELECT repeat(md5(random()::text), 6) FROM generate_series(1,#{ROWS})")
end
db.close

bench("seed #{FILES} x 1 MiB files") do
  buf = Bytes.new(1 << 20)
  FILES.times do |i|
    Random::Secure.random_bytes(buf)
    File.write(File.join(storage, "blob-#{i}.bin"), buf)
  end
end

ActiveBackup.configure do |c|
  c.store = ActiveBackup::LocalStore.new(File.join(workdir, "backups"))
  c.database_url = DB_URL
  c.paths = [storage]
  c.app = "backup_bench"
  c.retention = ActiveBackup::RetentionPolicy.new # keep all
end

size_db = 0
bench("create (db + files)") do
  entry = ActiveBackup.create(name: "bench.tar.gz")
  size_db = entry.size
end
puts("%-34s %8.2f MB" % ["archive size", size_db / 1_000_000.0])

bench("restore (verify + pg_restore + files)") do
  admin.exec("DROP DATABASE #{DB_NAME}")
  admin.exec("CREATE DATABASE #{DB_NAME}")
  ActiveBackup.restore("bench.tar.gz")
end

# reference: system tar+gzip over the same file tree
bench("ref: system tar czf files only") do
  Process.run("tar", ["-czf", File.join(workdir, "ref.tar.gz"), "-C", workdir, "storage"],
    output: Process::Redirect::Inherit)
end
ref_size = File.size(File.join(workdir, "ref.tar.gz"))
puts("%-34s %8.2f MB" % ["ref archive size (files only)", ref_size / 1_000_000.0])

db = DB.open(DB_URL)
count = db.scalar("SELECT count(*) FROM bench_rows").to_s.to_i
db.close
puts "rows after restore: #{count}"

admin.exec("DROP DATABASE #{DB_NAME}")
admin.close
rm_tree(workdir)
puts "OK"
