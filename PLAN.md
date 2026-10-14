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
- [x] `db/schema.cr` — аналог schema.rb: дамп 1:1 с оракулом 8.1.4
      (байт-в-байт) + `crails db:schema:load` round-trip (2026-10-03)
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
- [~] Devise-совместимая аутентификация (P0 готов: oracle 26 кейсов 26/26 devise 4.9.4 + юниты 11; bcrypt byte-compatible с pepper; sessions = Warden-замена; recoverable/confirmable/HTTP-роуты — P1)
- [x] JWT: access+refresh ротация (API/PWA/сервис-токены) (HS256 OpenSSL, opaque refresh + ревок, кросс-чек с ruby-jwt)
- [x] rails_hello — интеграционное приложение на полном стеке (1:1-зеркало bench/rails_hello: railties+action_pack+action_view+AR; HTTP-оракул 9 кейсов 9/9 против Rails 8.1.4; по ходу чинены action_pack status_code/render-CT и action_view Erubi-trim/form_tag)

## Фаза 2 — продакшен-готовность (порядок: 7 → 11 → 12 → 15)

### Iteration 7 — очереди/кэш/pubsub: PG по умолчанию, Redis — опция ✅ (2026-10-03)
Гексагональный pass: каждый новый адаптер пишется против явного порта —
module-интерфейса (`ActiveJob::Adapter`, `ActiveSupport::Cache::CacheStore`,
`ActionCable::SubscriptionAdapter::PubsubAdapter`), `include` вместо
наследования; общие контракт-спеки порта прогоняют все адаптеры.
Существующие `abstract class Store`/`Base` остаются как 1:1-Rails-API,
включая модуль-порт внутри.
- [x] ActiveJob-очередь на PG + recurring jobs (cron в очереди):
      `ActiveJob::SolidQueue::Adapter` (skip-locked, priority DESC+FIFO,
      scheduled-гейтинг, stale-claim reclaim) + `ActiveJob::Cron`
      (семантика fugit) + `RecurringTask` с дедупом (task_key, run_at);
      оракул 15 кейсов с настоящего solid_queue 1.2.4 + fugit 1.12.1,
      зеркало 1:1 + юнит-кроны; Redis-очередь (list+zset, контракт-спек)
- [x] кэш-сторы: memory/file/PG/Redis — порт `CacheStore`, оракул с
      настоящей RedisCacheStore (AS 8.1.4), один контракт-спек на все
      четыре стора (269/269 сюита active_support)
- [x] Cable pubsub: PG LISTEN/NOTIFY + Redis-адаптер — порт
      `PubsubAdapter`, оракул с настоящего ActionCable 8.1.4 Redis
      (одни кейсы для обоих адаптеров, 25/25 сюита action_cable)
- [x] bench: `results/201-solid-queue.md` (PG durable ~480 enq/s /
      1.8k drain/s; Redis ~41k jobs/s vs Sidekiq 1.4k),
      `results/202-pubsub.md` (PG 35k broadcast/s, Redis 109k; доставки
      339k / 982k в секунду)

### Iteration 11 — observability + deploy ✅ (2026-10-03)
Oracle-first по AGENTS.md: `railties.cr/oracle/observability_cases.rb`
(20 кейсов с настоящего Rails 8.1.4 production: `Rails::HealthController`
/up + /up.json, X-Request-Id UUID v4 + passthrough, 404-страница, строки
Started/Processing/Completed) → `observability_expected.yml`; зеркало
`railties.cr/spec/observability_spec.cr` — 23/23. Отклонения (в футере
спека): `CRails::HealthController` vs `Rails::`, Completed без скобки
Views/AR/GC, /up без ETag/Cache-Control; JSON-лог и /metrics — расширения
(Rails 8 не шипает их из коробки; `ActiveSupport::LoggerJsonFormatter`
не существует).
- [x] JSON-логи с request_id (`config.log_json`, production-дефолт,
      `CRAILS_LOG_JSON=1`), текстовый лог в формате Rails 8 с тегом
      `[request_id]`; X-Request-Id/X-Runtime на каждый ответ
- [x] `/up` + `/up.json` (семантика Rails health, до роутинга) +
      `/metrics` Prometheus (counter + histogram + rss, формат 0.0.4)
- [x] OTel-трейсы zero-config (`src/otel.cr`): OTLP/JSON POST на
      `{OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`, server-span на запрос;
      нет env — nil-check на горячем пути
- [x] graceful shutdown (SIGINT/TERM → drain → exit 0, pidfile
      tmp/pids/app.pid) + zero-downtime через `CRAILS_REUSE_PORT=1`
- [x] `crails deploy user@host[:dir]`: release-сборка → scp →
      db:migrate → рестарт рядом + TERM старому (smoke-проверено на
      localhost; end-to-end по ssh — при появлении реального хоста)
- [x] bench `results/500-observability.md`: оверхед текст-лога в шуме
      (83.7k → 91.0k RPS), JSON-лог −3.8% (80.5k), RSS +0–80 KB

### Iteration 12 — гигиена безопасности
- [~] rate limiting (2026-10-03): `rate_limit to:, within:` в action_pack
      (оракул `action_pack.cr/oracle/rate_limit_expected.yml` — 18 кейсов
      с actionpack 8.1.4: 429, бакеты по ip/`by:`, `with:`-обработчик,
      `name:`/`scope:`, `only:`, фиксированное окно, NullStore отключает;
      зеркало `railties.cr/spec/rate_limit_spec.cr` 17/17 поверх
      ActiveSupport::Cache-портов; по пути чинены Cache#increment —
      окно от первого запроса, добавлен NullStore — и
      Notifications.instrument — публикация события при исключении,
      как в Rails). Отклонения: `by:`/`with:` — Symbol-имя метода
      (нет instance_exec), в payload request — path, within — String
- [~] secure-by-default cookies/headers, CSP nonce: middleware-стек
      готов (2026-10-04) — `config.middleware` поверх `HTTP::Handler`
      (порт `ActionDispatch::MiddlewareStack`, оракул 8.1.4 — 29
      кейсов, зеркало 29/29; дефолт RequestId→RequestLogger→
      ShowExceptions→Head, конвейер извлечён из `Application#call`;
      `crails middleware`; Rack::Head-порт: HEAD→GET + отброс тела,
      Content-Length 0; X-Runtime `%.6f`; Cookies/Session/Flash
      остаются controller-side — documented deviation; бенч
      `results/501-middleware.md` −3% RPS). Осталось: сами
      secure headers/CSP-мiddleware поверх стека
- [~] CSRF-защита (2026-10-05): порт
      `ActionController::RequestForgeryProtection` 8.1.4 —
      `protect_from_forgery with: :exception/:null_session/:reset_session`
      (+`only:/except:`, `skip_forgery_protection`), токены wire-1:1
      (BREACH-маска pad-XOR, глобальный HMAC-SHA256 "!real_csrf_token",
      per-form HMAC "#{path}##{method}", param или X-CSRF-Token,
      Crypto::Subtle fixed-length), origin-проверка
      (`forgery_protection_origin_check`), JS-ответы не-XHR GET →
      `InvalidCrossOriginRequest`; обе ошибки → 422 в лестнице
      ShowExceptions; `form_with`/`form_tag` вставляют hidden-токен,
      `csrf_meta_tags`; генератор включает защиту в
      ApplicationController + meta-теги в layout. Оракул 28 кейсов с
      настоящего actionpack 8.1.4 (`action_pack.cr/oracle/csrf_cases.rb`,
      bare-стек Cookies/CacheStore/Flash/ShowExceptions, реальные
      cookie-jar'ы, DETERMINISTIC) — зеркало
      `railties.cr/spec/csrf_spec.cr` 28/28; E2E `crails new`: POST без
      токена 422, с X-CSRF-Token из meta 200. По пути чинены латентные
      баги: неработавший `skip_before_action` (интерполяция символа в
      FILTERS не разрешалась) и cookie round-trip сессии (write
      кодировал encode_www_form, read не декодировал). Отклонения:
      конфиг глобальный (config.action_controller.*-стиль), form_options
      — именованные аргументы action:/method:, кастомные strategy-
      классы и `store: :cookie` — P2
- [ ] sandboxed миграции
- [ ] `crails check` (пассивный анализ в духе Brakeman)

### Iteration 13 — Vite-интеграция (P0 готов, 2026-10-05)
Модель vite_rails: Vite остаётся npm-инструментом, Crystal — manifest +
хелперы + раздача. P0 закрывает production-флоу qp2 (vite build →
манифест → рендер → отдача ассетов):
- [x] `ViteRuby::Manifest` + `ViteHelper` в action_view.cr — оракул
      15 кейсов с настоящих vite_rails 3.0.19 / vite_ruby 3.9.2
      (`action_view.cr/oracle/vite_cases.rb` → `vite_expected.yml`,
      версии — из Gemfile.lock qp2; bare ActionView-контекст +
      фикстура-манифест формата vite 5/6), зеркало
      `action_view.cr/spec/vite_spec.cr` 15/15. Хелперы:
      `vite_asset_path`, `vite_javascript_tag` (script-ESM +
      modulepreload импортов + stylesheet css-чанков),
      `vite_stylesheet_tag`, `vite_image_tag`; байты вывода байт-в-байт
      (включая смешанные стили: modulepreload без `/`, stylesheet со
      слэшем). Отклонения: dev-server/HMR — P1, config/vite.json не
      парсится (class-свойства + env CRAILS_VITE_MANIFEST), type: —
      String вместо Symbol
- [x] `CRails::Middleware::Static` (порт ActionDispatch::Static 8.1.4)
      в railties.cr — оракул 14 кейсов с настоящего actionpack
      (`oracle/static_cases.rb` → `static_expected.yml`: GET/HEAD,
      кандидаты path/.html/index.html, CT по расширению, прекомпрессия
      br/gz по Accept-Encoding + Vary, traversal-блок, pass-through,
      HEAD без тела), зеркало `spec/static_spec.cr` 14/14. Включён
      первым в дефолтный стек; CRails-дефолт: `/vite/assets/*` →
      `Cache-Control: immutable` (хешированные имена, crails заменяет
      Thruster/CDN). Отклонения: Range/304 — P2. E2E: demo-приложение
      раздаёт public/turbo.js → 200 text/javascript через дефолтный
      стек
- [~] P1: dev-прокси на vite-сервер ✅ (2026-10-05):
      `CRails::Middleware::ViteDevProxy` (railties.cr/src/vite_dev.cr,
      реф ViteRuby::DevServerProxy vite_ruby 3.9.2) — в дефолтном стеке
      только в dev (`CRails.env.development?`/`CRAILS_VITE_DEV=1`), до
      Static; проксирует /@vite,/@id,/@fs,/@react-refresh,/src,
      /node_modules,/vite/ на CRAILS_VITE_HOST:PORT (127.0.0.1:5173),
      Host-rewrite + X-Forwarded-*; ws-upgrade с
      Sec-WebSocket-Protocol: vite-hmr сплайсится с TCP-сокетом vite
      (CRails-расширение — Rack::Proxy upgrade не умеет); vite недоступен
      → pass-through. Dev-теги action_view: `vite_client_tag`
      (/vite/@vite/client), `vite_react_refresh_tag` (CDATA-преамбула),
      entrypoints в dev без манифеста — оракул 13 кейсов с настоящих
      vite_rails 3.0.19/vite_ruby 3.9.2 (`action_view.cr/oracle/
      vite_dev_cases.rb` → `vite_dev_expected.yml`), зеркало
      `spec/vite_spec.cr`; транспорт — `railties.cr/spec/vite_dev_spec.cr`
      (фейковый vite HTTP+WS, 10/10). Осталось: `crails dev`
      (supervisor двух процессов; задел Iteration 15); ~~P2: генератор
      `crails new --vite` + importmap-режим~~ → importmap-режим закрыт
      Iteration 17 (importmap.cr), `--vite`-флаг остаётся P2

### Iteration 14 — send_file/send_data (✅ 2026-10-05)
Порт `ActionController::DataStreaming` + `ActionDispatch::Http::
ContentDisposition` (actionpack 8.1.4). Oracle-first: оракул 12 кейсов
с настоящего actionpack (`action_pack.cr/oracle/data_streaming_cases.rb`
→ `data_streaming_expected.yml`: дефолты, вывод CT по расширению,
двойной Content-Disposition с percent-escape — включая не-ASCII имена
(`%3F`-замена как в bare-геме), disposition nil, url_based_filename,
inline+status, MissingFile), зеркало
`railties.cr/spec/data_streaming_spec.cr` 13/13.
- [x] `send_data(data, filename:, type:, disposition:, status:,
      content_type:)` + `send_file(path, ..., url_based_filename:)`:
      CT без charset, Content-Transfer-Encoding: binary, стрим файла
- [x] `ActionController::MissingFile` → 404 в railties-лестнице
      (аналог rescue_responses Rails)
- [x] отклонения: Range для send_file — P2; MIME-вывод — подмножество
      Rack::Mime; `type:` — String (Symbol-алиасы — P2). Сюиты:
      railties 151/151, action_pack 54/54, action_view 124/124

### Iteration 15 — supervision (доступность без BEAM)
- [ ] роли бинарника: `crails server|worker|scheduler|supervise`
      (веб никогда не исполняет джобы в проде)
- [ ] супервизор: N×web + M×worker, backoff-перезапуск, memory watchdog
- [ ] bench отказов: `kill -9` воркера/веба, retry джобы, RSS-лимит

### Iteration 17 — importmap.cr (✅ 2026-10-05)
Порт `importmap-rails` 2.2.3 (отдельная шарда `importmap.cr/`):
`pin`/`pin_all_from` + importmap-теги. Oracle-first по AGENTS.md:
оракул 21 кейс с настоящего гема (`importmap.cr/oracle/importmap_cases.rb`
→ `importmap_expected.yml`: pin с `to:`/`preload:`/CDN-урл, pin_all_from
`under:`/`to:` c index-чомпингом, pretty-JSON, preloaded-пути с
entrypoint-фильтрацией, digest, полный стек тегов), зеркало
`spec/importmap_spec.cr` 17/17, байты — байт-в-байт. Интеграция:
хелперы в `ActionController::Base`, `/javascripts/*` из `app/javascript`
через `Middleware::Static`, `crails new` генерирует `config/importmap.cr`
+ layout с `javascript_importmap_tags`. Закрывает «importmap-режим» из
P2 Iteration 13. Quirk'и гема сохранены (glob без `.mjs`, кэш
`cache_key`). Отклонения: packager (jsDelivr) и SRI — P2, file-`draw`
→ block-DSL. Бенч `bench/results/204-importmap.md` (~11.6× на рендере
тегов). См. importmap.cr/PLAN.md.

## Фаза 3 — дифференциаторы (после продакшен-релиза)

- [~] **Iteration 8** — live_view.cr P0 готов: серверная часть Phoenix
      LiveView 1.2.12 (stateful fiber, Channels V2 wire-протокол,
      statics/dynamics-диффы, handle_event/handle_info) + официальный
      JS-клиент vendored немодифицированным. Оракул с настоящего
      Phoenix (oracle/app, транскрипт 11 кейсов, зеркало 8/8 спеков),
      headless-Chromium E2E (join→mount→click→diff→DOM), бенч
      `results/400-liveview.md` (~52–61k ev/s vs Phoenix 39–88k,
      RSS 14 MB vs 129 MB). PWA-генерация и live_component/uploads —
      отдельным заходом (см. live_view.cr/PLAN.md)
- [~] **Iteration 16** — action_bot.cr P0 готов (2026-10-04): боты
      из коробки, единый контракт сообщений (DeliveryAdapter /
      StreamingDelivery / IngressAdapter / WebhookVerification —
      module-порты Iteration 7). Oracle 39 кейсов: фикстуры Telegram
      валидируются настоящим telegram-bot-ruby 2.8.1 (oracle/vendor),
      WhatsApp — схема Cloud API; исходящие пейлоады байт-в-байт с
      документацией API. 19/19 спеков (оракул + фейк-API-серверы:
      sendMessage/editMessageText-стриминг, HMAC-verify, hub.challenge,
      getUpdates-поллер, SSE). Встраивание в приложение:
      `crails generate bot` (app/bots/ + монтирование /bot/webhooks +
      /bot/sse + config/bots.yml), `crails bot:poll`; E2E-смоук
      crails new → generate → webhook 403/200/404 + доставка ответа
      ботом. Задел на эпоху ИИ: reply.stream — единый конвейер
      чанки→платформа(edits)/веб(SSE), к которому будущий отдельный
      шард ActiveAgent (агентский цикл + Tool + LLM-провайдеры)
      подключится без изменения бот-контракта; имя ActiveAgent
      для него оставлено сознательно.
      Осталось: bench 600-bots, P1 deliver_later/conversations/Slack
- [~] **Iteration 17** — active_agent.cr (ИИ-агенты; не порт гема —
      интерфейс с нуля по исследованию: Anthropic Building Effective
      Agents, OpenAI Agents SDK, LangGraph, pydantic-ai, ruby
      active_agent): агент = цикл LLM+инструменты, module-порты
      `Provider` (LLM-провайдеры — аналог QueueAdapter; термин
      индустриальный, Brain отброшен), `Tool` (compile-time JSON
      Schema — typed input, описание обязательно, ACI), `Memory`
      (P1). Мультимодальность (content-parts: текст+изображения) —
      в P0-контракте. Run/Step — каждый шаг видим и в аудите;
      max_steps обязателен; стрим — `Proc(String, Nil)`-эмиттер,
      мост к ActionBot reply.stream без зависимости шардов.
      Oracle: wire-фикстуры провайдеров (байт-в-байт пейлоады) +
      цикл на Providers::Test без сети. P2: interrupt/resume (HITL
      на solid_queue), handoffs.
      **P0 готов (2026-10-04)**: контракты + цикл + Providers::Test +
      OpenAICompatible-движок (wire-оракул 6 кейсов байт-в-байт:
      tools/tool_calls/мультимодал/SSE-чанки; полный HTTP-флоу
      против фейк-сервера) + провайдеры openai/zai/kimi/deepseek/
      lmstudio/vllm/ollama (свои ENV/эндпоинты/модели поверх
      общего wire), ProviderError (статус+тело API), compile-time
      диспетчер тулзов, 21/21 спеков. Live-смоук ZAI: wire до
      api.z.ai доходит, авторизация ок — на аккаунте нет баланса
      (429), спек скипается до пополнения. Осталось:
      Anthropic-провайдер, мосты (эмиттер→ActionBot/SSE, ask_later),
      P1/P2.
- [x] **Iteration 19** — turbo.cr ✅ (2026-10-04): порт turbo-rails
      2.0.20 (Turbo Streams) — StreamsTagBuilder (7 действий + refresh
      + кастомные), StreamsChannel/Broadcasts, Broadcastable-миксин
      (broadcasts/broadcasts_to на after_commit, GlobalID-lite,
      suppressing), _later-джобы через ActiveJob, view-хелперы
      (turbo_stream_from/turbo_frame_tag), HTTP-формат
      text/vnd.turbo-stream.html в action_pack (respond_to,
      #{action}.turbo_stream.erb, http-фоллбэк redirect). Oracle
      60 кейсов с настоящего turbo-rails (oracle/cases.rb), зеркало
      6/6 групп; регресс соседей зелёный (AS 269 / AV 109 / AP 53 /
      AC 25 / AJ 56). Пререквизиты: MessageVerifier в active_support
      (HMAC-hexdigest), dom_id/record_identifier и статические
      tag_options в action_view, AVPartialLocal-алиас (инвариантность
      генериков). Demo: /notes живёт на Turbo Streams (broadcasts →
      prepend/replace/remove через /cable + destroy.turbo_stream.erb),
      vendored @hotwired/turbo + мини-cable-connector; E2E-смоук
      spec/e2e_smoke.cr PASSED. Бенч results/401-turbo-streams.md
      (рендер тега 2.1–2.7M/s, броадкаст 1.3–1.8M/s, fanout ×10
      12.7–18.5M deliveries/s). Отклонения: renderer-seam вместо
      ApplicationController.render, kwargs → named args (turbo.cr/
      PLAN.md).
- [x] **Iteration 20** — kiq.cr ✅ (2026-10-05): порт Sidekiq 8.1.7 →
      `Kiq` (`include Kiq::Job`, `kiq_options`, `perform_async/in/at/
      bulk/inline`, `set(...)`, Client/push_bulk, Launcher с fiber-
      воркерами и scheduled-poller, retry-математика count⁴+15+jitter,
      morgue/dead-set, `Kiq::Queue/Stats/ScheduledSet/RetrySet/
      DeadSet`, middleware-цепочки client/server, `Kiq::Testing`
      fake!/inline!/disable!, ActiveJob-адаптер `ActiveJob::KiqAdapter`).
      Wire-совместим с настоящим sidekiq: те же ключи Redis
      (queue:*/queues/schedule/retry/dead/stat:*), пейлоад с
      epoch-ms и jid-hex-24 — джобу ставит sidekiq-клиент, выполняет
      Kiq, и наоборот (фикс-пейлоад в spec/unit_spec.cr). Oracle-first
      по AGENTS.md: `kiq.cr/oracle/cases.rb` — 29 кейсов с настоящего
      sidekiq 8.1.7 (Ruby 3.4.5 + Redis DB 15, DETERMINISTIC повторным
      прогоном), зеркало `spec/oracle_spec.cr` 29/29 без правок кейсов;
      + юниты 7/7 (interop, weighted queues, graceful stop, AJ-адаптер,
      Testing) — сюита 36/36. Bench `results/203-kiq.md`: ~26k jobs/s
      конец-в-конец (8 воркеров, один процесс, RSS ~10 MB) vs sidekiq
      8.1 ~1.4k (из 201). Отклонения задокументированы в kiq.cr/PLAN.md
      (compile-time registry классов джоб, RuntimeError-маппинг для
      `raise "str"`, poller без Lua, middleware-инстансы вместо классов).
      P2: capsules, процессный heartbeat. Web UI готов (Iteration:
      `Kiq::Web` — порт Sidekiq::Web 8.1.7, оракул 94/94 маркера).
      CLI-бинарник `kiq` (`src/kiq_cli.cr`, `rake build:kiq`): флаги
      sidekiq-стиля (-c/-q[,weight]/-t/-v/-V), TERM/INT graceful +
      TSTP quiet, boot-ping Redis, retry-цикл при потере соединения;
      джобы запекаются сборкой (`KIQ_REQUIRE=... shards build kiq` —
      runtime `-r` в Crystal невозможен). CLI-спек гоняет бинарник
      end-to-end (активен после сборки bin/kiq); ручной E2E: baked-job
      выполняется, TSTP останавливает выборку, TERM → exit 0 + flush
      статистики.
- [x] **Iteration 18** — action_mcp.cr ✅ (2026-10-06): приложение
      становится MCP-сервером — порт wire-поведения официального Ruby
      SDK `mcp` 1.7.0 (вендорен в oracle/vendor): Streamable HTTP
      `/mcp` stateless+JSON (POST JSON-RPC 2.0: initialize с
      negotiation/ ping / tools list / call / resources-prompts стабы;
      нотификации → 202; parse/batch/Accept/CT/GET/DELETE гварды).
      Oracle 28 кейсов (Rack::MockRequest против настоящего
      StreamableHTTPTransport) → expected.yml; зеркало 28/28
      байт-в-байт через ServerController. Экспорт `ActiveAgent::Tool`
      (`tools`-макрос, compile-time диспетчер) + `agent(SupportAgent,
      "...")` — агент как MCP-инструмент (wrapper-тул, `.ask`).
      Монетизация: `ActionMCP.authenticate` (Bearer → ApiKey со
      скоупами read/write через `ActionMCP.mcp_scope` в теле тула,
      403 -32002), квоты Cache#increment фиксированным окном (429
      -32003), учёт `mcp:usage:<identity>` для биллинговой
      recurring-джобы, аудит `mcp.tools_call` (Notifications).
      Сюита 41/41; соседи зелёные (active_agent 21, action_pack 153,
      railties 309). По пути: латентный баг `Tool#input` (пустые поля —
      `[ ]` без типа) и re-feed raw body в `__merge_body_params`
      (action_pack). MCP-клиент (consuming, McpToolSource) остаётся в
      active_agent P2 — exposing и consuming в разных шардах, общий
      знаменатель — контракт Tool. Отклонения: только stable
      legacy-lifecycle (без SSE/сессий/modern envelope), гейтвей —
      CRails-расширение. Детали: action_mcp.cr/PLAN.md
- [~] **Iteration 9** — streaming-first ✅ (2026-10-06): порт
      `ActionController::Live` 8.1.4 (`action_pack.cr/src/live.cr`) —
      chunked/SSE-стриминг с backpressure (буфер 10, SizedQueue-семантика
      на Sync-примитивах) и отменой fiber'а экшена при disconnect
      (ClientDisconnected у заблокированного и следующего write).
      Oracle-first: `oracle/live_cases.rb` → `live_expected.yml` (28
      кейсов с настоящего actionpack 8.1.4 + puma 6.6.1: SSE-wire
      байт-в-байт, Buffer-семантика, транспорт — chunked-фрейминг,
      send_stream, ошибки до/после commit, HTTP/1.0, disconnect),
      зеркало `railties.cr/spec/live_spec.cr` 28/28 (полный стек за
      реальным HTTP::Server, сырые сокеты). Экшен — в отдельном
      fiber'е, pump в запросном; SSE/send_stream/`response.stream`;
      implicit render пропускается после коммита стрима. Bench
      `results/402-sse.md` (bench/crails_sse + rails_sse): SSE-fanout
      ~482–622k events/s vs Rails+Puma 31–41k (~15×), chunked
      ~710–887k/s vs ~115k, first-token 1.16 vs 1.97 мс, storm 200
      disconnects → отмена за 120 мс / RSS 22 МБ (1000 → 264 мс).
      Отклонения — в шапке src/live.cr
- [x] **Iteration 10** — type-safe params + OpenAPI compile-time codegen ✅
      (2026-10-06): `ActionController::TypedParams` (action_pack.cr,
      `src/typed_params.cr`) — DSL `typed_params(:create) do
      required :title, String, min_size: 3 ... end` генерирует класс
      с типизированными геттерами (compile-checked) + хелпер
      `<action>_params`; семантика 1:1 с dry-schema 1.13.4 (оракул
      42 кейса `oracle/typed_params_cases.rb` → expected.yml: verdict,
      коарсинг dry-types Params, дерево ошибок, output; зеркало
      42/42 без правок кейсов); `TypedParams::Invalid` → 422 JSON в
      railties-лестнице (E2E 4/4). OpenAPI-кодген (`src/openapi.cr`):
      документ 3.0.3 из роутов + compile-time реестра схем (path
      params, requestBody JSON Schema для POST/PATCH/PUT, query для
      GET), реверс-валидация настоящим openapi3_parser 0.10.1
      (`oracle/verify_openapi.rb`), раздача встроенным контроллером —
      `openapi "/openapi.json"` одной строкой в drawer'е. Бенч
      `results/205-typed-params.md`: ~30× vs dry-schema (887k vs 30k
      ops/s), ~11.6× vs Ruby-permit, внутри Crystal ~0.58× от
      нетипизированного permit. Отклонения — action_pack.cr/PLAN.md
      (Iteration 10). P2: TS-клиент из документа (ECOSYSTEM api-only
      bootstrap), формы `a[b]` в query-схеме
- [ ] **Iteration 13** — DX: hot-reload шаблонов/i18n без рекомпиляции,
      `crails watch` (rebuild + zero-downtime), error pages
- [~] **Iteration 14** — active_backup.cr: бэкапы БД/файлов, сторы,
      retention через recurring jobs, restore-тест в CI
      **P0 готов (2026-10-06)**: дифференциатор (не порт гема).
      Архив = один .tar.gz (свой ustar writer/reader, двусторонний
      оракул с системным GNU tar: наши архивы читает `tar -tzf/-xzf`,
      наш Reader — фикс-архив oracle/fixtures/gnu.tar); db.dump —
      настоящий pg_dump -Fc, restore — настоящий pg_restore (Debian
      multi-version: бинари пиннятся под мажор сервера через
      /usr/lib/postgresql/<ver>/bin — иначе pg_dump 17 к серверу 16
      даёт нечитаемый формат 1.16 / SET transaction_timeout);
      files/<name>/... — деревья каталогов; manifest.json пишется
      последним (обрезанный архив не парсится), sha256 каждого члена,
      сверка при restore (порча байта → CorruptBackupError). Сторы —
      узкий порт `ActiveBackup::Store` (module-interface): LocalStore,
      MemoryStore (S3 — P1). RetentionPolicy keep_last/keep_days
      (новейший не удаляется никогда, бэкапы без времени — тоже);
      retention применяется после каждого create и в prune().
      Recurring: `ActiveBackup::BackupJob < ActiveJob::Base`
      (perform = create + prune), регистрируется RecurringTask-ом в
      шедулере приложения; события create/restore.active_backup.
      Restore-тест в CI (spec/restore_spec.cr): сидинг PG (bytea,
      unicode, timestamptz, массивы) + файлов (вложенность, бинарники,
      unicode-имена) → create → tar -tzf → DROP DATABASE + rm -rf →
      restore → побайтовая сверка БД и файлов; повторный restore с
      clean: true. Сюита 18/18 (скипы без PG/tar). По пути обойдён баг
      codegen Crystal 1.21 (вложенные yield-блоки в месте вызова —
      copy-with-hash вынесен в метод). Отклонения: symlink/PAX — P2,
      инкрементальные/шифрование — P2, crails backup:* CLI — P1.
      Детали: active_backup.cr/PLAN.md

## Backlog идей — Clean Rails / дядя Боб (вклеивать по мере итераций)

Идеи Роберта Мартина, принятые как направление. Конкретика внедрения
решается в соответствующих итерациях, здесь — чтобы не потерялось.

1. **Screaming Architecture**: опция `crails new --layout=domain` —
   фичевые каталоги (`app/notes/`, `app/billing/`: model + controller +
   views внутри фичи) вместо техслоёв; классический layout — дефолт.
2. **Пакетные принципы (ADP/SDP)**: CI-проверка, что граф зависимостей
   шардов (по shard.yml) ацикличен — механика для README-обещания №9;
   правило: меняемся только в сторону стабильных шардов (всё зависит
   от active_support, а не наоборот).
3. **ISP — узкие порты**: module-интерфейсы Iteration 7 держим
   маленькими (QueueAdapter = enqueue + enqueue_at, не god-порт);
   опциональные способности — отдельными интерфейсами
   (`RecurringAdapter` включает `QueueAdapter`, проверка
   `adapter.is_a?(RecurringAdapter)`), никогда не сужаем старый контракт.
4. **Развилка recurring jobs**: дефолт — встроенный шедулер-супервизор
   поверх `QueueAdapter#enqueue_at` (работает с любым адаптером,
   встраивается в роль `crails scheduler`, Iteration 15); оптимизация —
   нативный recurring в PG-адаптере через `RecurringAdapter`.
5. **Тест-пирамида**: к интеграционным оракулам добавить слой быстрых
   юнит-спеков без IO для чистой логики (образцы: `Diff.compute`,
   `LiveView::Token`) — правило «чистая логика тестируется без сокетов».
6. **LSP/OCP через оракулы**: каждая новая фича рождается с оракулом до
   кода (AGENTS.md) — оракульные спеки и есть механическая проверка
   подстановки реализаций; расширение контракта = новый контракт рядом,
   старый не трогаем.
7. **Интеграция active_model.cr (Фаза AM, план — PLAN_REMAINING.md)**:
   шард написан и оракулен (127 кейсов + test-suite 8.1.4), но AR от
   него не зависит. Высветлить валидации/Errors/dirty/callbacks из
   active_record.cr в active_model.cr (AR включает AM, как в
   оригинале), публичный API AR не меняется; form objects
   (`ActiveModel::Model`) становятся доступными приложению без БД.
8. **Чистый режим (`--layout=domain`) — инвариант, а не конвенции**.
    Сервисы/формы сами по себе архитектурой не являются (завести
    папочки можно на любом фреймворке). Ядро — правило зависимостей,
    проверяемое компилятором: `app/domain` собирается отдельной
    единицей с whitelist-ом require'ов; домен, потянувший action_pack
    или turbo, НЕ КОМПИЛИРУЕТСЯ (`crails arch` — читаемая ошибка).
    Это то, чего Rails не мог дать в принципе (интерпретатор), и
    настоящее наполнение имени Clean Rails. Состав чистого режима:
    - слои: `app/domain` (чистые структуры, порты объявляет
      ПРИЛОЖЕНИЕ: Repository, Clock), `app/adapters` (AR-репозитории,
      SystemClock — реализуют порты), транспорт (controllers/jobs),
      `config/composition.cr` — единственная точка склейки;
    - `Result(T, E)` в active_support: доменные отказы — не
      исключения; транспорт маппит union ошибок в 422/404, union
      кормит OpenAPI-кодген (Iteration 10);
    - транзакция как порт юзкейса (UoW), не `note.transaction`
      в модели;
    - доменные события (п. 9) как способ связи домена с доставкой;
    - fake-адаптеры к каждому порту как часть контракта: FakeClock,
      FakeRepo (in-memory), Events::Recorder — юнит-тест юзкейса без
      БД/сокетов; по AGENTS.md-логике контракт без fake — недописан.
    Диал, а не догма: дефолт — Rails-образный layout; полная развязка
    оправдана для сложных доменов (финтех-ledger, escrow), для CRUD —
    осознанный выбор простоты. Генераторы `crails generate service|form`
    работают в обоих режимах (форма = AM::Model поверх typed_params).
9. **Доменные события вместо Broadcastable в модели**: нейтральный
   in-process event bus (`CRails::Events`, compile-time реестр
   подписок — п.2 про отсутствие рантайм-магии); модель публикует
   доменные события (Note::Created/Viewed/Destroyed), Turbo-слой
   подписывается адаптером в инициализаторе доставки. Rails-1:1
   `include Turbo::Broadcastable` остаётся как быстрый путь, но
   благословленный чистый путь — события; demo переписать на него
   (сейчас Note знает про /cable и DOM-таргеты — UI в домене).
10. **Тест-швы времени**: `travel_to`/`freeze_time` в active_support
    (оракул с AS 8.1.4) — recurring/dunning-логика тестируется
    юнитно; в чистом режиме время — порт Clock, в Rails-режиме —
    `CRails.now` вместо прямого `Time.utc`.

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
