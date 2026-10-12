# Клиентский драйвер 402-sse bench — общий для CRails и Rails серверов
# (голые TCP-сокеты, никакой HTTP-клиентской буферизации: считаем
# события/чанки/байты на лету).
#
# Режимы:
#   client fanout   HOST PORT CONNS EVENTS  — N конкурентных SSE-стримов
#   client chunked  HOST PORT N             — один chunked-поток
#   client first    HOST PORT N             — N последовательных коннектов,
#                                              avg/p95 first-token latency (d=1ms)
#   client storm    HOST PORT N             — N коннектов читают 1 событие и
#                                              рвут соединение; затем опрос
#                                              /stats до active=0

require "json"
require "socket"

HOST = ARGV[1]? || "127.0.0.1"
PORT = (ARGV[2]? || "4200").to_i

def open_sock
  # NOTE: без tcp_nodelay на клиентском сокете — с ним отключение
  # клиента детектится сервером на порядок медленнее (RST/ACK-паттерн)
  TCPSocket.new(HOST, PORT)
end

def read_until(sock, marker : String) : Int32
  # читаем до появления *marker* в потоке (первый SSE-фрейм / конец
  # заголовков + байт тела); возвращаем прочитанные байты
  buf = IO::Memory.new
  slice = Bytes.new(4096)
  loop do
    n = sock.read(slice)
    return 0 if n == 0
    buf.write(slice[0, n])
    return buf.bytesize if buf.to_s.includes?(marker)
    return buf.bytesize if buf.bytesize > 200 # страховка от вечного тика
  end
end

mode = ARGV[0]? || "fanout"

case mode
when "fanout"
  conns = (ARGV[3]? || "50").to_i
  events = (ARGV[4]? || "2000").to_i
  # счётчики — мутабельные боксы (Atomic — struct: запись через
  # arr[i].set терялась бы на копии элемента)
  counters = Array.new(conns) { [0_i64] }
  t1 = Time.monotonic
  conns.times do |i|
    spawn do
      sock = open_sock
      sock << "GET /events?n=#{events}&d=1 HTTP/1.1\r\nHost: b\r\n\r\n"
      buf = IO::Memory.new
      slice = Bytes.new(16_384)
      loop do
        n = sock.read(slice)
        break if n == 0
        buf.write(slice[0, n])
        break if buf.to_s.ends_with?("0\r\n\r\n")
      end
      sock.close
      counters[i][0] = buf.to_s.scan("data: ").size.to_i64
    end
  end
  total = 0_i64
  while true
    finished = 0
    total = 0_i64
    counters.each do |c|
      v = c[0]
      finished += 1 if v > 0
      total += v
    end
    break if finished == conns
    sleep 5.milliseconds
  end
  t2 = Time.monotonic
  secs = (t2 - t1).total_seconds
  puts "RESULT fanout conns=#{conns} events=#{events} " \
       "total_events=#{total} secs=#{secs.round(3)} " \
       "events_per_s=#{(total / secs).round(0)}"
when "chunked"
  n = (ARGV[3]? || "100000").to_i
  t1 = Time.monotonic
  sock = open_sock
  sock << "GET /chunked?n=#{n} HTTP/1.1\r\nHost: b\r\n\r\n"
  buf = IO::Memory.new
  slice = Bytes.new(16_384)
  loop do
    got = sock.read(slice)
    break if got == 0
    buf.write(slice[0, got])
    break if buf.to_s.ends_with?("0\r\n\r\n")
  end
  sock.close
  t2 = Time.monotonic
  secs = (t2 - t1).total_seconds
  chunks = buf.to_s.scan("chunk-").size
  puts "RESULT chunked n=#{n} secs=#{secs.round(3)} " \
       "chunks_per_s=#{(chunks / secs).round(0)} " \
       "mb_per_s=#{(buf.bytesize.to_f / 1024 / 1024 / secs).round(2)}"
when "first"
  n = (ARGV[3]? || "200").to_i
  latencies = [] of Float64
  n.times do
    t1 = Time.monotonic
    sock = open_sock
    sock << "GET /events?n=1&d=1 HTTP/1.1\r\nHost: b\r\n\r\n"
    read_until(sock, "data:")
    t2 = Time.monotonic
    sock.close
    latencies << (t2 - t1).total_milliseconds
  end
  latencies.sort!
  avg = latencies.sum / latencies.size
  p95 = latencies[(latencies.size * 0.95).to_i]? || latencies.last
  puts "RESULT first n=#{n} avg_ms=#{avg.round(3)} p95_ms=#{p95.round(3)}"
else
  abort "unknown mode #{mode}"
end
