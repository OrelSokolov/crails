# CRails — план до продакшена

> Порт Rails 8 на Crystal: API 1:1, неймспейс `CRails`, ERB→ECR,
> вся магия — compile-time. Подробности по каждому шарду — его `PLAN.md`.
> Исследование API: `/home/oleg/egui.cr/plans/crails-api-research.md`.

**Продакшен-готовность = Фаза 1 (порт) + Фаза 2 (надёжность и деплой).**
После закрытия их боксов снимаем предупреждение EXPERIMENTAL.
Фаза 3 — дифференциаторы, порядок после релиза: 8 → 9 → 10 → 13 → 14.

Правило каждой итерации (AGENTS.md): начинать с интеграционных
тест-кейсов — скачать оригинальный гем, снять синтетику + взять его
тесты; обе реализации проходят одни тесты без правок тестов.
Каждая итерация заканчивается бенчем в `bench/results/`.

## Фаза 1 — порт ядра

### Iteration 0 — Hello World ✅ (2026-10-02)
- [x] `crails new/server/routes/watch`, роутер, контроллер, ECR, консоль
- [x] bench `000-hello`: ~142k RPS / 16 MB RSS / старт 10 мс (vs Rails 233 / 110 MB / 950 мс)

### Iteration 1 — active_support.cr ✅ (2026-10-02)
Тест-first: oracle/cases.rb (189 кейсов) снят с настоящего activesupport
8.1.4 → oracle/expected.yml; оригинальные минитесты rails/rails v8.1.4 —
в oracle/rails-tests/. 226 спеков зелёные. Задокументированные
отклонения: sec..weeks остаются Time::Span (затенение Int#minutes ломает
stdlib); String→Symbol в рантайме невозможен (symbolize_keys —
идентичность, I18n-локали — String); `included do` → `macro included`.
- [x] тест-кейсы с оригинального activesupport (portable подмножество)
- [x] core_ext P0: Object/String/Hash/Array/Enumerable/Numeric
- [x] Duration (`2.days`), дата-математика, `Time.zone`/TimeWithZone (минимум)
- [x] `Concern`, `delegate`, `Notifications`
- [x] `Cache` (memory+file), I18n (yml), `NumberHelper`

### Iteration 2 — active_record.cr ✅ (2026-10-02)
Тест-first по AGENTS.md: oracle/cases.rb (78 кейсов записи) и
oracle/migrations.rb (4 нормализованных дампа схемы) сняты с настоящего
activerecord 8.1.4 → expected.yml / migrations_expected.yml; порт
воспроизводит их без правок тестов. 108 спеков зелёные. Отклонения:
`val_numericality_not_int` непереносим (статическая типизация — строка в
Int-колонку не компилируется); rollback `drop_table` без блока —
IrreversibleMigration 1:1; `through`/polymorphic-ассоциации — P2.
- [x] CRUD-запись: create/save/update/destroy, dirty-tracking
- [x] валидации, коллбэки
- [x] ассоциации: belongs_to/has_many/has_one (+dependent)
- [x] миграции DSL + `crails db:migrate/rollback/schema:dump` (schema.yml)
- [x] bench `100-ar-read` / `101-ar-crud` vs Rails

### Iteration 3 — action_view.cr + action_pack.cr (полный MVC-контур) ✅ (2026-10-02)
- [x] layouts/partials/collection-render (counter 0-based, spacer), `content_for`/`provide`
- [x] хелперы text/number/url/tag, output-safety (SafeString)
- [x] FormBuilder (`form_with` + поля); `fields_for` — перенесено в Iteration 5
- [x] strong params, cookies/session/flash, `rescue_from`, `respond_to`
      (`send_file`/`send_data` — Iteration 5)
- [ ] fragment cache (Iteration 5)
- [x] bench full-page vs Rails — `bench/results/300-full-page.md` (~65× RPS)

Отклонения от Rails (задокументированы в PLAN.md шардов): locals-хеш в
`render partial:` — Crystal-литерал `{"k" => v}` вместо рубишного `{k: v}`;
`permit`/`expect` принимают вложенные фильтры hash-аргументом; session/flash
cookie-store без подписи; CSRF-слоя нет; newline-семантика ERB выровнена
по Rails 8.1 `load_defaults` (chomp одного `\n` у action-шаблонов).

### Iteration 4 — active_job.cr + action_cable.cr
- [x] ActiveJob: `perform_later/perform_now`, retry/discard DSL, адаптеры (inline/test/async-fiber-пул) — oracle 28 кейсов, 29/29 + смоук async
- [x] Cable: channels/стримы/протокол + ws-слой /cable (fiber-per-connection) — oracle 14/14 + интеграционный ws-спек
- [x] bench: `results/200-jobs.md` (CRails ~1M jobs/s vs Rails async 32k vs Sidekiq 1.4k), `results/300-websockets.md` (~260k msg/s vs Rails 6.7k, 300 коннектов 0 потерь)

### Iteration 5 — хвост стека (порядок по необходимости)
- [~] action_mailer.cr — P0+deliver_later готовы (оракул 28 кейсов 30/30, SMTP-диалог против фейк-сервера; P1 хвост: .with/observers/previews)
- [~] active_storage.cr — P0 готов (оракул 27 кейсов 29/29: Disk-сервис, Blob/Attachment на AR, has_one_attached, purge; variants/S3/Mirror — P1)
- [~] action_text.cr — P0 готов (оракул 48 кейсов 48/48: lexbor-фрагменты, plain-text, safe-list sanitize + trix-layout, RichText/has_rich_text с autosave; аттачменты/sgid — P1)
- [~] action_mailbox.cr — P0 готов (оракул 29 кейсов 29/29: InboundEmail + raw_email blob, Router String/Regex/:all, lifecycle статусов, before_processing с bounced!-haltом; ingress/incinerate — P1)

### Iteration 6 — devise.cr + минимальные гемы
- [ ] Devise-совместимая аутентификация
- [ ] JWT: access+refresh ротация (API/PWA/сервис-токены)
- [ ] rails_hello — интеграционное приложение на полном стеке

## Фаза 2 — продакшен-готовность (порядок: 7 → 11 → 12 → 15)

### Iteration 7 — очереди/кэш/pubsub: PG по умолчанию, Redis — опция
- [ ] ActiveJob-очередь на PG + recurring jobs (cron в очереди)
- [ ] кэш-сторы: memory/file/PG/Redis
- [ ] Cable pubsub: PG LISTEN/NOTIFY + Redis-адаптер
- [ ] bench: джобы/сек PG vs Redis vs Sidekiq; pubsub msg/сек

### Iteration 11 — observability + deploy
- [ ] JSON-логи с request_id, `/healthz` + `/metrics` (Prometheus)
- [ ] OTel-трейсы через `Notifications` (zero-config)
- [ ] graceful shutdown, zero-downtime restart (передача socket'а)
- [ ] `crails deploy` = scp бинаря + миграции

### Iteration 12 — гигиена безопасности
- [ ] secure-by-default cookies/headers, CSP nonce
- [ ] rate limiting, sandboxed миграции
- [ ] `crails check` (пассивный анализ в духе Brakeman)

### Iteration 15 — supervision (доступность без BEAM)
- [ ] роли бинарника: `crails server|worker|scheduler|supervise`
      (веб никогда не исполняет джобы в проде)
- [ ] супервизор: N×web + M×worker, backoff-перезапуск, memory watchdog
- [ ] bench отказов: `kill -9` воркера/веба, retry джобы, RSS-лимит

## Фаза 3 — дифференциаторы (после продакшен-релиза)

- [ ] **Iteration 8** — live_view.cr (stateful fiber, DOM-морфинг,
      handle_event/handle_info) + PWA-генерация (manifest, service
      worker, Web Push VAPID)
- [ ] **Iteration 9** — streaming-first: SSE/chunked из блока/джобы,
      backpressure, отмена fiber'а при disconnect
- [ ] **Iteration 10** — type-safe params + OpenAPI compile-time codegen
- [ ] **Iteration 13** — DX: hot-reload шаблонов/i18n без рекомпиляции,
      `crails watch` (rebuild + zero-downtime), error pages
- [ ] **Iteration 14** — active_backup.cr: бэкапы БД/файлов, сторы,
      retention через recurring jobs, restore-тест в CI

## Definition of Done (продакшен)

- [ ] rails_hello работает на полном стеке Фаз 1–2, деплой одной командой
- [ ] все спеки зелёные; тесты 1:1 с оригиналами проходят без правок
- [ ] bench-набор опубликован: hello / ar-crud / jobs / ws / 1m-load
- [ ] снят флаг EXPERIMENTAL из README и шардовых PLAN.md

## Чего НЕ будет (осознанно)

- Zeitwerk/autoload/dev-reload классов — компилируемый язык; `crails watch` = rebuild.
- Рантайм `constantize` по строкам — только compile-time registry.
- Dynamic finders (`find_by_email`), `with_options`, `StringInquirer`
  (заменён `CRails.env.production?`).
- Поддержка чужих Ruby-гемов и плагинов, переопределяющих ядро.

Зависимости (не пишем своё): crystal-pg, crystal-redis-shard, stdlib
OpenSSL/Bcrypt, lexbor, libvips; YAML/JSON — stdlib.
