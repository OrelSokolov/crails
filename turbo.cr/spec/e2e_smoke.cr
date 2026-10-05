# E2E smoke: Turbo Streams в demo (сервер на :3001).
# 1) подписка на Turbo::StreamsChannel с signed_stream_name со страницы /notes
# 2) POST /notes (создание)  -> turbo-stream prepend по /cable
# 3) GET /notes/:id (просмотр, views+1) -> turbo-stream replace
# 4) POST /notes/:id/destroy c Accept: text/vnd.turbo-stream.html
#    -> turbo-stream HTTP-ответ + remove по /cable

require "http"
require "json"

BASE = "http://127.0.0.1:3001"
WS   = "ws://127.0.0.1:3001/cable"

client = HTTP::Client.new(URI.parse(BASE))
page = client.get("/notes").body
signed = page[/signed-stream-name="([^"]+)"/, 1]
raise "no signed-stream-name on /notes" unless signed
puts "page subscribed: signed-stream-name ok (#{signed.size} chars)"

messages = Channel(String).new(32)
socket = HTTP::WebSocket.new(URI.parse(WS))
spawn do
  socket.on_message do |frame|
    if (msg = JSON.parse(frame)["message"]?)
      # turbo-stream HTML приходит строкой: достаём raw, не to_json
      # (экранированные кавычки ломают проверки ниже).
      messages.send(msg.raw.as?(String) || msg.to_json)
    end
  end
  socket.run
end
sleep 0.3

ident = {"channel" => "Turbo::StreamsChannel", "signed_stream_name" => signed}.to_json
socket.send({"command" => "subscribe", "identifier" => ident}.to_json)
sleep 0.3

def wait_stream(messages, what : String, contains : String, timeout = 5) : String
  deadline = Time.monotonic + timeout.seconds
  found = Channel(String).new(1)
  spawn do
    while (m = messages.receive)
      if m.includes?(what) && m.includes?(contains)
        found.send(m)
        break
      end
    end
  end
  select
  when m = found.receive
    puts "broadcast ok: #{what} #{contains}"
    m
  when timeout(timeout.seconds)
    raise "no #{what} broadcast with #{contains}"
  end
end

# --- create: broadcast prepend через cable ---------------------------------
resp = client.post("/notes", form: {"title" => "e2e turbo", "body" => "smoke", "color" => "sky"})
raise "create -> #{resp.status}" unless resp.status.redirection?
# prepend-броадкаст: тег + отрендеренная карточка приходят одним фреймом
wait_stream(messages, "prepend", %q{turbo-stream action="prepend" target="notes"})

# --- show: views+1 -> broadcast replace карточки ---------------------------
note_id = page[/\/notes\/(\d+)/, 1]? # любая старая заметка не годится: нужна новая
resp = client.get("/notes")
new_id = resp.body[/href="\/notes\/(\d+)"[^>]*>[\s\S]{0,400}?e2e turbo/, 1]
raise "created note not on index" unless new_id
client.get("/notes/#{new_id}")
wait_stream(messages, "replace", %q{turbo-stream action="replace"})

# --- destroy: HTTP turbo_stream + cable remove -----------------------------
resp = client.post("/notes/#{new_id}/destroy", headers: HTTP::Headers{
  "Accept" => "text/vnd.turbo-stream.html, text/html;q=0.9",
})
body = resp.body
raise "destroy turbo_stream -> #{resp.status} #{resp.headers["Content-Type"]?}" unless
  resp.status.ok? && body.includes?(%q{turbo-stream action="remove"}) && new_id
puts "http turbo_stream ok: remove note_#{new_id}"
wait_stream(messages, "remove", "note_#{new_id}")

puts "E2E SMOKE PASSED"
exit 0
