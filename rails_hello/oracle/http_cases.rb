# Integration HTTP cases for rails_hello — the SAME harness runs against
# the Ruby reference (bench/rails_hello) and the CRails port (this dir):
#
#   ruby oracle/http_cases.rb record http://localhost:3100   # vs Rails
#   ruby oracle/http_cases.rb check  http://localhost:3101   # vs CRails
#
# Fixture format: "case_id\tescaped_value" (same \n/\t/\r protocol as the
# other oracles). Values are "status|content-type|normalized-body".
#
# Normalizations (framework-invariant output only):
#   - "Served by <name> <version> (Ruby|Crystal)." → "Served by SERVER."
#   - long digit runs (bench-<ms> timestamps) → "TS"
#   - 404 bodies are framework error pages → body recorded as "ERROR_PAGE"
#
# Precondition: seeded DB (see `make seed-rails` / `make seed-crails`):
#   posts 1..3 = [first post/hello world/3, second post/nil/0,
#                 "third & <post>"/nil/42]

require "net/http"
require "uri"
require "json"

mode, base = ARGV[0], ARGV[1]
abort "usage: ruby http_cases.rb record|check URL" unless mode && base

def escape(s)
  s.gsub("\\", "\\\\\\\\").gsub("\n", "\\n").gsub("\t", "\\t").gsub("\r", "\\r")
end

def normalize(body)
  body
    .gsub(/Served by \S+ [\d.]+ \((?:Ruby|Crystal)\)\./, "Served by SERVER.")
    .gsub(/\d{10,}/, "TS")
end

def case_value(uri, method = :get, body = nil)
  uri = URI.join(uri, "") unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  http = Net::HTTP.new(uri.host, uri.port)
  req = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
  req["Accept"] = "*/*"
  if body
    req.set_form_data(body)
  end
  res = http.request(req)
  norm = normalize(res.body.to_s)
  # 404 pages (routing miss, RecordNotFound) are framework error pages:
  # body AND content-type are framework-specific → record placeholders.
  if res.code.to_i == 404
    norm = "ERROR_PAGE"
    return "#{res.code}|ERROR_CT|#{norm}"
  end
  "#{res.code}|#{res['content-type']}|#{norm}"
end

base_url = base
cases = {}

# --- read-only pages over the seeded data ---------------------------------
cases["root_page"] = case_value(URI.join(base_url, "/"))
cases["posts_index"] = case_value(URI.join(base_url, "/posts"))
cases["posts_show_1"] = case_value(URI.join(base_url, "/posts/1"))
cases["posts_show_2"] = case_value(URI.join(base_url, "/posts/2"))
cases["posts_show_3_specials"] = case_value(URI.join(base_url, "/posts/3"))
cases["posts_show_missing_404"] = case_value(URI.join(base_url, "/posts/424242"))
cases["unknown_route_404"] = case_value(URI.join(base_url, "/nope"))

# --- create (appends post id=4) --------------------------------------------
created = case_value(URI.join(base_url, "/posts"), :post, {})
cases["posts_create"] = created
# verify what the app actually stored (title pattern, not just 200)
cases["posts_created_fetch"] = case_value(URI.join(base_url, "/posts/4"))

path = File.expand_path("../expected.yml", __FILE__)
if mode == "record"
  File.open(path, "w") do |f|
    cases.each { |id, v| f.puts "#{id}\t#{escape(v)}" }
  end
  puts "recorded #{cases.size} cases to #{path}"
else
  expected = {}
  File.read(path).each_line do |line|
    next unless line.include?("\t")
    id, v = line.split("\t", 2)
    expected[id] = v.chomp
  end
  failed = 0
  cases.each do |id, v|
    want = expected[id]
    if escape(v) == want
      puts "#{id}: ok"
    else
      failed += 1
      puts "#{id}: FAIL\n  got:  #{escape(v)}\n  want: #{want}"
    end
  end
  abort "#{failed} failing case(s)" if failed > 0
  puts "#{cases.size}/#{cases.size} ok"
end
