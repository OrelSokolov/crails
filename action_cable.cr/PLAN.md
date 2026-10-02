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

## Статус (Iteration 4 — P0+P0.5 готовы, бенч снят)

- Oracle: `oracle/cases.rb` → `oracle/expected.yml`, 14 кейсов сняты с
  actioncable 8.1.4 (канальная семантика через FakeConnection-харнесс +
  протокольные константы). Зеркало: `spec/oracle_spec.cr` — 14/14 зелёные.
- WS-слой (P0.5): `src/connection.cr` + `src/server.cr` — Rails-JSON-протокол
  (welcome/subscribe/confirm_subscription/message/ping), fiber-per-connection,
  монтируется на любой HTTP::Server через `Server#ws_handler`. Покрыт
  интеграционным спеком `spec/ws_spec.cr` (реальный сервер + клиент).
- AsyncAdapter active_job: `bench/crails_jobs` — см. `bench/results/200-jobs.md`
  (~1M jobs/s no-op). WS-бенч: `bench/crails_ws` + `bench/loadgen/ws_load.cr` —
  см. `bench/results/300-websockets.md` (~260k msg/s при 300 коннектах).
- Реализовано (`src/`): `protocol.cr` (INTERNAL-константы 1:1),
  `subscription_adapter.cr` (Base + Test), `channel.cr`
  (Channel::Base: subscribed/unsubscribed/stream_from/stop_all_streams/
  transmit/reject/params + perform_action-диспетчер), `connection.cr`,
  `server.cr`, `ruby_inspect.cr`.
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

## Фазы

- P0: connection + channel DSL, stream_from/transmit/reject, async-адаптер,
  JSON-протокол (совместимость с @rails/actioncable).
- P1: PG/Redis pubsub (кросс-процессность), broadcast_to/stream_for,
  identified_by полный, periodically, remote disconnect.
- P2: command-коллбэки, статистика, health-check.

## Готово, когда

два браузера с официальным `@rails/actioncable` JS-клиентом подключаются
к `/cable`, состоят в канале и получают broadcast'ы друг друга.

## Зависимости

active_support.cr, railties.cr (HTTP-сервер), crystal-pg / redis.
