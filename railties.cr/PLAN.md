# railties.cr — CRails core + CLI `crails`

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `CRails` — **единственное** отличие от Rails. Оценка: ~75–80%
(dev-reload/zeitwerk не переносимы в принципе — компилируемый язык).

## CRails-модуль (1:1 к `Rails`)

- `CRails.application` (`< CRails::Application`), `CRails.env`
  (`CRails.env.production?` — enum-предикаты, ощущение то же),
  `CRails.root`, `CRails.logger`, `CRails.cache`, `CRails.groups`,
  `CRails.version`
- `CRails.application.routes` (draw + named helpers),
  `.credentials`, `.config`, `.initialize!`, `.load_seed`,
  `.message_verifier(name)`
- Config: `config/application.cr` + `config/environments/{development,
  test,production}.cr`; `config.time_zone`, `config.cache_store`,
  `config.middleware.use/insert_before/insert_after/swap/delete`
  **✅ сделано (2026-10-04)** — порт `ActionDispatch::MiddlewareStack`
  (`src/middleware.cr`): стек = `HTTP::Handler`-цепочка (`#next`),
  соответствие по имени как в Ruby; дефолтный стек RequestId →
  RequestLogger → ShowExceptions → Head (+ терминальный Dispatcher);
  оракул с 8.1.4 (`oracle/middleware_cases.rb`, 29 кейсов: семантика
  стека, дефолт Rails, HEAD/Rack::Runtime/insert_before по HTTP),
  зеркало `spec/middleware_spec.cr`; `crails middleware` (= rake
  middleware). Cookies/Session/Flash остаются controller-side —
  documented deviation (нет request-env для предзагрузки jar'ов);
  constructor-args у узлов нет (конфиг читается на call), `X-Runtime`
  теперь `%.6f` как Rack::Runtime. Бенч `bench/results/501-middleware.md`
  (−3% RPS на цепочке). Остальное (time_zone, cache_store, generators,
  config.x, after_initialize) — P1, `config.generators`,
  `config.x.*` (Hash для произвольных ключей),
  `config.after_initialize`, `initializer "name" do |app|`
- Credentials: `config/credentials.yml.enc` + master key (как в Rails)
- Middleware-стек по умолчанию (аналогичный состав): HostAuthorization,
  SSL, Static, RequestId, RemoteIp, Logger, ShowExceptions, Cookies,
  Session, Flash, CSP — **RequestId/Logger/ShowExceptions/Head готовы
  (2026-10-04, см. выше); HostAuthorization/SSL/Static/CSP — P1**;
  Cookies/Session/Flash — controller-side (deviation)
- Sessions: cookie_store по умолчанию (signed), cache_store

## CLI: `crails` (вместо `rails`)

Внешний бинарник (не вшит в приложение) + `bin/crails` в проекте:

- `crails new app` — каркас: Gemfile→shard.yml, config/, app/
  (models/controllers/views/channels/jobs/mailers), bin/, db/
- `crails server / s` (сборка + запуск, `-e/-p/-b`), `crails console`
  (REPL поверх скомпилированного приложения — отдельная сборка с
  интерпретатором-циклом), `crails routes`, `crails runner "code"`,
  `crails about`, `crails version`
- `crails generate/destroy g` — `model controller scaffold migration
  mailer job channel mailbox helper` (+ `config.generators` шаблоны)
- `crails db:create/migrate/rollback/prepare/seed/schema:load/version/
  migrate:status/reset/system:change` (через active_record.cr)
- `crails credentials:edit/show`, `crails encrypted:edit/show`,
  `crails secret`, `crails stats`, `crails initializers`,
  `crails middleware`, `crails dev:cache`
- `crails watch` — rebuild+restart при изменениях (замена dev-reload)
- `crails bench` — быстрый прогон сценариев из bench/

## Чего не будет

Zeitwerk/autoload (`zeitwerk:check`), `to_prepare`-семантика,
`Rails.application.secrets` (удалён и в Rails 8), StringInquirer-магия,
`load_defaults`-каскады (один фиксированный набор дефолтов).

## Реализация

- Boot: явный список компонентов (compile-time), конфиг — типизированный
  объект; initializer'ы — статический упорядоченный список.
- Генераторы: шаблоны `.ecr` в `railties.cr/templates/`.
- `crails console`: **✅ сделано (2026-10-02) на [icr.cr](https://github.com/OrelSokolov/icr.cr)**
  — `crails c` подгружает приложение через `src/console.cr` (генерится:
  requires + ActiveRecord-подключение из DATABASE_URL / config/database.yml)
  и сразу доступны запросы (`Post.count`, `Post.where(...)`). Бэкенд icr:
  replay (перекомпиляция строки, ~5s со всем приложением) по умолчанию,
  live-интерпретатор через `CRAILS_CONSOLE_LIVE=1` (нужен interpreter-
  build кристалла).

## Фазы

- P0 (Iteration 0): `crails new` + `crails server` для hello world,
  роутер, контроллер, ECR-вьюха, `crails routes`, `crails watch`.
- P1: `generate` (model/controller/scaffold/migration), `db:*`,
  environments-конфиг, credentials, middleware-стек API
  **(middleware-стек — готов, 2026-10-04)**.
- P2: console, runner, stats/initializers/about, dev:cache.

## Готово, когда

`crails new blog && cd blog && crails server` поднимает приложение
с нуля без ручных правок файлов.

## Статус

### Iteration 13 — generators (generate/destroy) ✅ (2026-10-05)
Oracle-first: `oracle/generators_cases.rb` — 41 кейс с Rails 8.1.4
(model/scaffold/controller/mailer/job/channel/mailbox/helper/migration/
resource_route: файловый вывод + stdout invoke/create/identical/route)
→ `oracle/generators_expected.yml`; зеркало `spec/generators_spec.cr`
(27/27; полный railties — 96/96).

- `src/generators/`: base (thor-подобный вывод, `--pretend`/`--force`/
  `--skip`, behavior :invoke/:revoke), fields/migration_builder/
  model_files, генераторы model/scaffold/controller/mailer/job/channel/
  mailbox/helper/migration; CLI-таблица `GENERATORS` в `src/cli.cr`,
  `crails destroy` = generate с behavior :revoke
- CRails-расширения (объясняют `patch src/app.cr`/`symlink` в выводе):
  `AppGlue.patch_requires` патчит `src/app.cr` requires для затронутых
  app/-директорий (нет zeitwerk); `AppGlue.ensure_shard` симлинкует
  фреймворк-шарды (mailbox → action_mailbox + active_storage)
- E2E (tmp-приложение): все 8 генераторов одной пачкой → db:migrate →
  `crystal build src/app.cr` — зелёный; REST scaffold 200/302 +
  404 на удалённой записи
- Зафиксированные при e2e: `ActionCable::Connection` (порт даёт
  конкретный класс, не `Connection::Base`); `require "../app/channels/
  application_cable/**"` перед `app/channels/**` (glob `**` даёт файлы
  корня раньше поддиректорий); `Base.migration_filename` — монотонные
  версии миграций (мigrator сортирует строго по version; идентичное
  имя при re-run `--force` остаётся `identical`);
  `AppGlue.ensure_active_storage_tables` — аналог
  `rails active_storage:install` (кодеген моделей читает db/schema.yml
  приложения); `ShowExceptions`: ActiveRecord::RecordNotFound → 404
  (матч по имени класса — railties_cr не зависит от active_record_cr)
- Отклонения от оракула (футер spec/generators_spec.cr): .cr-файлы;
  `ActiveRecord::Migration` без [8.1]; spec/ вместо test/; `invoke
  spec` вместо `invoke test_unit`; явные `to:` в route; ручные URL во
  вьюхах; raw `<form>`; патчи src/app.cr + symlink — расширения; JS/
  importmap для channel пропущены

### Iteration 12a — middleware-стек ✅ (2026-10-04)
Oracle-first: `oracle/middleware_cases.rb` — 29 кейсов с Rails 8.1.4
(семантика `ActionDispatch::MiddlewareStack`: use/unshift/
insert_before/insert_after/swap/delete/delete!/move_before/move_after,
сообщения об ошибках, equality/inspect/build; дефолтный стек реального
приложения; HTTP-поведение: HEAD /up через Rack::Head, X-Runtime
Rack::Runtime, insert_before кастомного middleware из конфига) →
`oracle/middleware_expected.yml`; зеркало `spec/middleware_spec.cr`.

- `src/middleware.cr`: `CRails::MiddlewareStack` (порт 1:1,
  соответствие узлов по имени, сборка через `HTTP::Handler#next`) +
  `CRails::Middleware::{RequestId, RequestLogger, ShowExceptions,
  Head, Dispatcher}` — конвейер `Application#call` извлечён в стек
- `config.middleware` в `CRails::Config`; инъекция приложения в
  middleware при сборке цепочки (аналог rack-аргумента `app`, без
  зависимости от глобала `CRails.application`)
- `crails middleware` / `bin/app middleware` — аналог `rake middleware`
- Head: HEAD диспетчеризуется как GET, тело отбрасывается через
  подмену `response.output`, Content-Length = 0 (как оракул 8.1.4)
- Отклонения (футер spec/middleware_spec.cr): RuntimeError → Exception
  (сообщения те же), узлы без constructor-args (конфиг на call-time),
  Cookies/Session/Flash не переносятся в стек, нет
  InstrumentationProxy (P2), дефолтный стек — только имеющие
  counterpart записи Rails 8.1 (маппинг в шапке middleware.cr)
- Бенч `bench/results/501-middleware.md`: −3% RPS за цепочку (A/B на
  одной машине); регресс соседей нет (railties 69/69, action_pack
  53/53)

### Iteration 11 — observability + deploy ✅ (2026-10-03)
Oracle-first: `oracle/observability_cases.rb` — 20 кейсов с Rails 8.1.4
production (GET /up HTML/JSON, X-Request-Id UUID v4 + passthrough, 404,
строки Started/Processing/Completed) → `oracle/observability_expected.yml`;
зеркало `spec/observability_spec.cr` — 23/23.

- `src/observability.cr`: request-id, health (`/up`, `/up.json` до
  роутинга), Prometheus `/metrics` (text 0.0.4: requests_total
  {method,status}, duration histogram, rss), лог-строки Rails-формата +
  JSON-режим (`config.log_json`: production-дефолт, `CRAILS_LOG_JSON=1`)
- `src/otel.cr`: zero-config OTLP/JSON-трейсы
  (`OTEL_EXPORTER_OTLP_ENDPOINT`/`..._HTTP` + `OTEL_SERVICE_NAME`);
  нет env → nil-check
- `Application#call`: X-Request-Id/X-Runtime, текст Started/Processing/
  Completed с тегом `[request_id]` или одна JSON-строка, 404 как HTML
- `Application#serve`: graceful shutdown (SIGINT/TERM → server.close →
  drain → exit 0), `CRAILS_REUSE_PORT=1` для zero-downtime, pidfile
  `tmp/pids/app.pid`
- `crails deploy user@host[:dir]`: release-сборка → scp → `db:migrate` →
  рестарт рядом + TERM старому (см. `src/deploy.cr`)

Отклонения от оракула (футер spec/observability_spec.cr):
`CRails::HealthController` vs `Rails::`; Completed без `(Views/AR/GC)`;
`/up` без ETag/Cache-Control. JSON-лог + `/metrics` — расширения CRails.

Bench: `bench/results/500-observability.md` — текст-лог в шуме baseline
(83.7k → 91.0k RPS), JSON −3.8%, RSS +0–80 KB.

## Зависимости

все шарды; CLI — отдельный shard `railties` с бинарником `crails`.
