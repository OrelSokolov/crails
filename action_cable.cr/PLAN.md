# action_cable.cr — порт ActionCable

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActionCable` — 1:1. Оценка: ~90%. На Crystal ложится
естественнее, чем на Ruby: fiber-per-connection поверх `HTTP::WebSocket`
(stdlib) вместо nio4r + thread pool.

## API 1:1

### Connection (`app/channels/application_cable/connection.cr`)
- `class Connection < ActionCable::Connection::Base`
- `identified_by :current_user` (N раз) — макрос: геттер/сеттер + регистр
- `def connect` / `def disconnect`; `reject_unauthorized_connection`
- `cookies` (через cookie_jar запроса на апгрейд) — аутентификация
  как в Rails
- `before_command/after_command/around_command`

### Channel (`< ApplicationCable::Channel < ActionCable::Channel::Base`)
- `def subscribed` / `def unsubscribed` (+ `before_subscribe/
  after_subscribe/before_unsubscribe/after_unsubscribe` с `if:/unless:`)
- `stream_from "room_#{id}" do |msg| end` (+ coder:), `stream_for @post`,
  `stop_stream_from/stop_stream_for/stop_all_streams`,
  `stream_or_reject_for`, `transmit(data, via:)`, `reject`, `params`,
  `connection`
- `periodically :transmit_progress, every: 5.seconds` / `periodically
  every: 3.minutes do ... end`
- Публичный метод канала = RPC-экшен для клиента: в Crystal —
  макрос-таблица диспетчеризации (разработчик пишет `def speak(data)` —
  работает так же, как в Rails)
- Class: `CommentsChannel.broadcast_to(@post, message)`,
  `broadcasting_for(target)`

### Сервер
- `ActionCable.server.broadcast(name, message)`,
  `ActionCable.server.remote_connections.where(current_user: u).disconnect`
- Монтирование на `/cable` (`mount_path`)
- Протокол: тот же JSON-протокол Rails (`command: subscribe/message`,
  ответы `welcome/subscription_confirmation/ping/disconnect`) —
  JS-клиент @rails/actioncable работает без изменений

### Config
`config/cable.yml`: `adapter:` async (in-process) / postgresql
(LISTEN/NOTIFY) / redis (pubsub) + `channel_prefix`;
`config.action_cable.*`: mount_path, allowed_request_origins,
worker_pool_size (fiber-пул), logger, log_tags.

## Реализация

- WebSocket-апгрейд + fiber-per-connection; сердце сервера — event loop
  не нужен, блокирующий IO на fiber'ах дёшев.
- Pubsub-адаптеры: Async (in-process канал), PG LISTEN/NOTIFY (crystal-pg),
  Redis (кристаллический redis-клиент). Протокол адаптера — как в Rails.
- Remote disconnect: внутренние per-connection каналы, как в Rails.
- Identifier'ы → per-connection fiber state.

## Статус (Iteration 5 — P1.5 fast broadcast готов, бенч снят)

- Oracle: `oracle/cases.rb` → `oracle/expected.yml`, 14 кейсов сняты с
  actioncable 8.1.4 (канальная семантика через FakeConnection-харнесс +
  протокольные константы). Зеркало: `spec/oracle_spec.cr` — 14/14 зелёные.
- WS-слой: `src/connection.cr` + `src/server.cr` — Rails-JSON-протокол
  (welcome/subscribe/confirm_subscription/message/ping), fiber-per-connection,
  ручной апгрейд в `Server::CableHandler` (прямой доступ к io для cork).
  Покрыт интеграционным спеком `spec/ws_spec.cr` (реальный сервер + клиент).
- P1.5 fast broadcast (Bun/uWS publish-аналог, см. секцию ниже):
  `src/cork_writer.cr` (cork-буфер + writer-fiber, 1 write на батч,
  frame-once API, backpressure cap 1 MiB + drop), `src/async_adapter.cr`
  (Async-адаптер, fast-реестр, encode-once конверт — дефолт сервера),
  `stream_from` без блока → fast-подписка. Бенчи: `results/310-ws-bun-matrix.md`
  (2.72M msg/s ≈ bun-publish 2.52M, ~6.5× bun-send), `results/300-websockets.md`
  (397k msg/s @ 300 коннектов, было 261k). Спеки 15/15.
- AsyncAdapter active_job: `bench/crails_jobs` — см. `bench/results/200-jobs.md`
  (~1M jobs/s no-op). WS-бенч: `bench/crails_ws` + `bench/loadgen/ws_load.cr`.
- Реализовано (`src/`): `protocol.cr` (INTERNAL-константы 1:1 + envelope
  builder), `subscription_adapter.cr` (Base + Test), `channel.cr`
  (Channel::Base: subscribed/unsubscribed/stream_from/stop_all_streams/
  transmit/reject/params + perform_action-диспетчер), `connection.cr`,
  `cork_writer.cr`, `async_adapter.cr`, `server.cr`, `ruby_inspect.cr`.
- Зафиксированные отклонения от Ruby API:
  - `transmit` публичный (в Ruby приватный; в Crystal нет `send`);
  - `streams` → публичный `stream_names` (для тестов);
  - `unsubscribe(channel, callback)` → `unsubscribe(channel)` — у Proc
    в Crystal нет identity;
  - params — `Hash(String, String)` вместо HashWithIndifferentAccess;
  - INTERNAL — именованные константы вместо гетерогенного хеша;
  - identified_by/cookies/periodically/stream_for/broadcast_to — P1.
- Семантика, снятая оракулом: transmit оборачивает в
  `{identifier:, message:}`; unsubscribe чистит streams до вызова
  `unsubscribed`; dispatch по публичным 0/1-арг методам подкласса
  (кроме lifecycle).

## Fast broadcast — перенос идей Bun/uWS publish (P1.5)

Контекст: `bench/bun_ws` — оригинальный бенч oven-sh (32 клиента, closed
loop). Bun `publishText` 4.17M msg/s против Bun `send` 159K (26×) — и это
не «быстрый WebSocket», а другой API fan-out'а. Разбор исходников
(`~/bun/packages/bun-uws/src/`):

| идея | Bun (publish) | наш текущий путь (P0.5) |
|---|---|---|
| кодирование | конверт сериализуется 1 раз — «палитра» `outgoingMessages`, подписчик получает `uint16`-индекс (`TopicTree.h:301`) | на каждого подписчика: `JSON.parse` + `to_json` + String-аллокации |
| fan-out | целиком нативный цикл по `drainableSubscribers`, JS не участвует | N вызовов `Proc(String, Nil)` |
| запись | cork: фреймы копятся в буфере лупа, drain в pre/post-handler → 1 `write` на сокет на итерацию (`App.h:514`, `LoopData.h`) | `@ws.send` на подписчика = syscall на сообщение на сокет |
| backpressure | `publishText` → -1 (queued) / 0 (dropped); drain останавливается на DROPPED | нет: блокирующая запись, медленный клиент стопит весь sweep |

Итого на 1 broadcast × N подписчиков сейчас: N парсингов, N сериализаций,
N Proc-вызовов, N syscall'ов, 0 батчинга. Замер P0.5: ~261k msg/s @ 300
коннектов (`bench/results/300-websockets.md`).

### Целевой дизайн (4 механизма)

1. **Fast-stream подписка (encode-once).** `stream_from` без блока
   регистрирует `(connection, identifier)` в реестре адаптера вместо Proc.
   Broadcast: конверт `{"identifier":…,"message":…}` строится один раз на
   уникальный identifier — message уже валидный JSON, встраивается как есть
   (raw-embedding, без parse→dump). Затем те же байты уходят всем
   подписчикам этого identifier.
2. **Per-connection cork.** Исходящие фреймы копятся в буфере соединения
   (двухбуферный swap под Mutex), writer-fiber соединения выгребает батч
   одним `io.write` — 1 syscall на сокет на батч. Аналог drain+cork: пока
   писатель пишет, новые сообщения накапливаются в следующий батч.
3. **Один писатель сокета.** Авто-понги stdlib (из fiber-читателя) и батчи
   writer-fiber сериализуются lock-обёрткой IO → нет интерливинга фреймов
   (заодно чинит существующую гонку ping-fiber vs broadcast-fiber).
4. **Backpressure.** Буфер капится (1 MiB); переполнение → drop сообщения +
   счётчик (семантика Bun DROPPED). Медленный клиент не стопит sweep.

Отличие от Bun: у нас fiber-модель, «итерация event loop» = батч
writer-fiber (пробуждение по каналу-флагу, порог — размер буфера), а не
pre/post-handler epoll. Кастомные коллбэки `stream_from(name) { |msg| }`
остаются на Proc-пути — семантика 1:1 с Rails.

### Совместимость и риски

- Протокол не меняется: oracle 14/14 и ws_spec должны остаться зелёными
  без правок тестов (меняется только путь доставки). Добавляется ws_spec
  на Async-адаптере (fast path) — тот же протокол end-to-end.
- Raw-embedding: сообщение с неканоничными пробелами не нормализуется,
  как после parse→dump (остаётся валидным JSON с тем же значением).
  Oracle сидит на Test-адаптере (Proc-путь) — не затронут.
- Монтаж `/cable` переходит с `HTTP::WebSocketHandler` на ручной upgrade
  (нужен прямой доступ к io для cork) — поведенчески то же, проверено
  standalone-вариантом `bench/bun_ws/chat-server.cr`.

### Бенчмарк-критерий (сравнение с Bun на их же клиенте)

- `bench/bun_ws/chat-server.crails.cr` — chat-сервер на `action_cable_cr`
  (`stream_from` fast path) в матрице run_all.sh против bun-publish /
  bun-send / node-ws. Цель: ряд bun-send и выше; syscalls/доставку меряем
  `strace -c -e write,writev`.
- `bench/crails_ws` (300-websockets): регресса быть не должно; цель —
  заметный рост с ~261k msg/s. Результаты → `bench/results/`.

### Этапы

- T1: Async-адаптер + fast-реестр + encode-once конверт.
- T2: cork-буфер + writer-fiber + 1 write на батч + IO-lock (п.2–3).
- T3: backpressure (cap + drop + счётчики, `buffered_amount`).
- T4: бенчи (`bench/bun_ws`, 300-websockets), отчёт в `bench/results/`.

## P1.6: Оптимизации WS-транспорта (backlog — не реализовано)

Обоснование: CPU, сожжённый на горячем пути, не исчезает — он украден у
соседей по процессу (scheduler-очередь других fiber'ов, GC-паузы,
вытеснение кэша). Поэтому дешёвый fan-out — это не «цифра в бенче», а
чужая p99-латентность под пиковой нагрузкой. Мера эффекта — тот же бенч
(`bench/bun_ws/run_all.sh`, база в `results/310-ws-bun-matrix.md`).

Память 95 MB против 42 MB у bun-publish — принятый размен: cork-буферы
мелкие на фоне реального Rails-приложения, не проблема.

### 1. Буферизованное чтение (главный кандидат)

Stdlib `WebSocket::Protocol` читает каждый входящий фрейм напрямую из
сокета: `read_fully` заголовка (2 байта) + `read_fully` payload = 2–3
`read`-сисколла на сообщение. Запись мы закрыли cork'ом (P1.5), чтение
осталось с P0.5. Аналог uWS: один большой `read()` на пробуждение, из
буфера парсится сколько влезло фреймов. Реализация: обёртка буферизованного
чтения под `Protocol` (по образцу `LockedImageIO` в `cork_writer.cr`).
Ожидание: минус 1–2 сисколла на каждое входящее сообщение.

### 2. JSON-фастпас на горячем пути

`handle_command` парсит каждое сообщение дважды (`JSON.parse(raw)` +
`JSON.parse(data["data"])`) — две аллокации дерева `JSON::Any` + хэши,
GC-давление растёт с throughput, а GC останавливает ВСЕ fiber'ы процесса.
Для broadcast-паттерна (`command == "message"`) — диспетчеризация без
полного парса: проверка подстрок `"command":"message"` / identifier,
полный JSON только для data. Порядок полей в клиентах @rails/actioncable
стабилен; чужие клиенты с другим порядком — фолбэк на полный парс.

### 3. Мелочи

- Кэш конвертов: несколько broadcast'ов за тик с одним identifier
  строят одну и ту же строку — мемоизировать на тик.
- Пул фрейм-буферов вместо `Bytes.dup` на батч в `CorkWriter`.
- Стек fiber'ов: ~290 КБ резидентно на коннект — тюнинг ради цели
  «100k коннектов на процессе» (ёмкость, не скорость).

### Куда не лезть

- Свой парсер RFC 6455 вместо stdlib: фрагментация, интерливинг
  control-фреймов, close-handshake — uWS шлифует это годами.
- io_uring: нет в Crystal stdlib, переписывание планировщика ради
  последних процентов.
- Busy-polling writer-fiber'ов: обмен CPU на латентность, бьёт по
  соседям — противоречит смыслу всего раздела.

## Фазы

- P0: connection + channel DSL, stream_from/transmit/reject, async-адаптер,
  JSON-протокол (совместимость с @rails/actioncable).
- P1: PG/Redis pubsub (кросс-процессность), broadcast_to/stream_for,
  identified_by полный, periodically, remote disconnect.
- P1.5: fast broadcast — идеи Bun/uWS publish: encode-once + cork-буфер +
  writer-fiber + backpressure (см. секцию выше). Готово, Iteration 5.
- P1.6: оптимизации WS-транспорта — буферизованное чтение, JSON-фастпас,
  мелочи (backlog, см. секцию выше).
- P2: command-коллбэки, статистика, health-check.


## Готово, когда

два браузера с официальным `@rails/actioncable` JS-клиентом подключаются
к `/cable`, состоят в канале и получают broadcast'ы друг друга.

## Зависимости

active_support.cr, railties.cr (HTTP-сервер), crystal-pg / redis.
