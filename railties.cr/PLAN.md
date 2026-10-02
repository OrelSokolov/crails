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
  (стек = `HTTP::Handler`-цепочка), `config.generators`,
  `config.x.*` (Hash для произвольных ключей),
  `config.after_initialize`, `initializer "name" do |app|`
- Credentials: `config/credentials.yml.enc` + master key (как в Rails)
- Middleware-стек по умолчанию (аналогичный состав): HostAuthorization,
  SSL, Static, RequestId, RemoteIp, Logger, ShowExceptions, Cookies,
  Session, Flash, CSP
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
  environments-конфиг, credentials, middleware-стек API.
- P2: console, runner, stats/initializers/about, dev:cache.

## Готово, когда

`crails new blog && cd blog && crails server` поднимает приложение
с нуля без ручных правок файлов.

## Зависимости

все шарды; CLI — отдельный shard `railties` с бинарником `crails`.
