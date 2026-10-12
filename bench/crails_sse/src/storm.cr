# Storm-клиент 402-sse bench: N коннектов читают ~200 байт вечного
# SSE-тикера и рвут соединение; затем опрос /stats до полного
# cancellation. Выделен из client.cr: инлайн-чтение в fiber'ах без
# helper-вызовов (с хелпером сокеты клиента закрывались GC-финализатором
# на середине чтения — «Closed stream»).

require "socket"
require "http/client"

HOST = ARGV[0]? || "127.0.0.1"
PORT = (ARGV[1]? || "4200").to_i
N = (ARGV[2]? || "200").to_i

t0 = Time.monotonic
N.times do
  spawn do
    sock = TCPSocket.new(HOST, PORT)
    sock << "GET /infinite HTTP/1.1\r\nHost: b\r\n\r\n"
    buf = IO::Memory.new
    slice = Bytes.new(4096)
    loop do
      n = sock.read(slice)
      break if n == 0
      buf.write(slice[0, n])
      break if buf.bytesize > 200
    end
    sock.close
  end
end

loop do
  break if Time.monotonic - t0 > 60.seconds
  # HTTP::Client: корректный Content-Length-фрейминг (Puma держит
  # keep-alive — gets_to_end на сыром сокете висит без EOF)
  body = HTTP::Client.get("http://#{HOST}:#{PORT}/stats").body
  if body.includes?("active=0") && body.includes?("cancelled=#{N}")
    rss = body.match(/rss_kb=(\d+)/).try(&.[1].to_i) || 0
    puts "RESULT storm n=#{N} cancel_ms=#{(Time.monotonic - t0).total_milliseconds.round(0)} rss_kb=#{rss}"
    exit 0
  end
  sleep 50.milliseconds
end
puts "RESULT storm n=#{N} TIMEOUT"
