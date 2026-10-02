# CRails — мастер-план

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Цель эксперимента: монолит Rails MVC на Crystal и цифры — сколько
пользователей, джобов и вебсокетов он выдерживает. «Новый король
стартапов» или «полный провал» — решат бенчмарки.

Полное исследование API: `/home/oleg/egui.cr/plans/crails-api-research.md`
(вердикт: ~85–90% ежедневного API Rails переносится 1:1 по ощущениям).

## Принципы

1. **API 1:1.** Имена методов, аргументы, kwargs — как в Rails 8.2
   (совместимо с кодом эпохи 3–8). Единственное исключение — неймспейс
   `CRails` вместо `Rails` (чтобы не конфликтовать) и ERB→ECR.
2. **Никакого рантайм-метапрограммирования внутри.** Все Rails-магии
   (boot-time `define_method`/`class_eval`) → Crystal-макросы,
   `{{ run(...) }}`-кодоген, compile-time registry'ы
   (`{{ @type.all_subclasses }}`).
3. **Crystal-стек:** HTTP::Server + HTTP::Handler (аналог middleware),
   fiber'ы вместо thread-pool'ов, crystal-pg, crystal-redis.
4. Каждая итерация заканчивается бенчмарком в `bench/`.

## Итерации

### Iteration 0 — Hello World (ПЕРВАЯ) ✅ (2026-10-02)
Минимальный `crails`: роутер `root "welcome#index"`, контроллер, ECR-view,
`crails server`. Без БД. См. `hello_world/PLAN.md`.
Метрика: RPS hello vs Rails 8 + Puma на той же машине, память, время
компиляции и старта. **Итоги: `bench/results/000-hello.md`**
(~142k RPS vs 233, 16 MB vs 110 MB RSS, старт 10 ms vs 950 ms).

### Iteration 1 — active_support.cr (ядро зависимостей)
`blank?/present?/presence/in?`, Duration (`2.days.ago`), дата-математика
(`beginning_of_day`, `next_week`), Inflector, `Concern`, `delegate`,
`Notifications`, `Cache` (memory+file), I18n (yml), `NumberHelper`.

### Iteration 2 — active_record.cr (ядро фреймворка) — 🔄 начата (read-срез)
Кодоген атрибутов из `schema.yml` (`{{ run }}`), Relation
(where/order/limit/joins/includes/pluck/find_each), CRUD, валидации,
коллбэки, `belongs_to/has_many/has_one`, миграции DSL (PostgreSQL).
Метрика: джобы CRUD и RPS «чтение из БД» vs Rails.
**Готово (2026-10-02): read-срез** — кодоген атрибутов, Relation-чтение,
подключение со всеми настройками; проверено на реальной базе
`data_lake_development`; 29 спеков. Осталось: CRUD-запись, валидации,
коллбэки, ассоциации, миграции + `crails db:*`, bench 100-ar-read.
Кодогену — конвенция `tenant_id` (опциональная колонка тенанта,
см. DIRECTIONS.md §H: мультитенанси будет модулем Фазы 3).

### Iteration 3 — action_view.cr
ECR-интеграция, layouts/partials, text/number/url-хелперы, FormBuilder,
`content_for`, fragment cache. **Full-page cache / статическая
генерация:** публикация контента → джоба рендерит статический HTML →
отдача с кэша; живые блоки (комментарии, счётчики) — Cable-виджеты
(DIRECTIONS.md §I: блог-движок = семечко экосистемы).

### Iteration 4 — action_cable.cr + active_job.cr
WebSocket-каналы на fiber'ах (fiber-per-connection), `broadcast_to`,
`stream_from`; ActiveJob: `perform_later`, retry/discard DSL,
fiber-pool адаптер.
Метрика: удержанные ws-коннекты; джобы/сек; compare vs Sidekiq+Rails.

### Iteration 5 — хвост фреймворка
action_mailer.cr (порт mail: MIME/SMTP), action_storage.cr (vips),
action_text.cr, action_mailbox.cr. Порядок по необходимости.

### Iteration 6 — devise.cr + минимальные гемы для рабочего приложения
Девайс-совместимая аутентификация + список минимальных зависимостей
(см. ниже). **JWT для API и PWA** (devise-jwt-модель): короткоживущий
access + refresh-ротация; тот же JWT-механизм — под VAPID Web Push
(Iteration 8) и сервис-токены для egui.cr-клиентов (§G).

## Фаза 2 — пост-порт: модернизация 2026 (после Iteration 6)

> Цель: то, чего нет у Rails-порта — дифференциаторы, которые оправдывают
> существование CRails, а не только скорость. Порядок = ценность/строки кода.

### Iteration 7 — очереди/кэш/pubsub: PG по умолчанию, Redis — опция
Адаптерная архитектура: ActiveJob-очередь (по умолчанию на PG,
Sidekiq-модель на Redis как опция), кэш-сторы (memory/file/PG/Redis),
Cable pubsub (PG `LISTEN/NOTIFY` по умолчанию, Redis — опция).
Стартуем на одном PG — меньше движущихся частей; Redis подключается
конфигом, когда нужен. Recurring jobs (cron) внутри очереди.
Метрика: джобы/сек PG vs Redis vs Sidekiq+Rails; latency очереди;
pubsub сообщений/сек; удержанные ws на обоих pubsub-адаптерах.

### Iteration 8 — live_view.cr (главный дифференциатор)
Сервер-driven UI поверх Cable: stateful fiber на подключение,
DOM-морфинг, `handle_event`/`handle_info`, формы и live reload без JS.
**PWA-генерация из коробки** (оболочка поверх LiveView):
`manifest.webmanifest` из конфига; service worker без Node —
ванильный JS + precache-список роутов из compile-time registry
(cache-first ассеты / network-first страницы / Background Sync для
офлайн-форм); Web Push (VAPID): подписки в AR, отправка джобами
(RFC 8291/8292 на stdlib OpenSSL), пуши когда PWA закрыта;
версионирование кэша по content-hash. Итог: веб-приложение
ставится на телефон как нативное, без App Store.
Метрика: удержанные liveview-сессии, RSS на сессию, latency
событие→рендер; Lighthouse PWA-аудит = installable.

### Iteration 9 — streaming-first ответы
SSE/chunked как граждане первого класса: `stream` из блока, из джобы,
из внешнего HTTP (LLM-прокси), backpressure, отмена fiber'а при
disconnect клиента, таймауты на стрим.
Метрика: одновременные стримы, p99 latency первого байта, поведение
при 10k резко отвалившихся клиентах (утечки fiber'ов/памяти).

### Iteration 10 — type-safe params + OpenAPI codegen
Декларативные схемы параметров (`params do ... end`): валидация +
каст + **генерация OpenAPI compile-time** — то, чего не может
динамический фреймворк. `/docs` из спеки.
Метрика: RPS с/без валидации (оверхед ~0), полнота спеки на тестовом
API.

### Iteration 11 — observability + deploy
JSON-логи с request_id, `/healthz` + `/metrics` (Prometheus),
OTel-трейсы через `Notifications` (запрос/БД/джоба — zero-config).
Graceful shutdown (drain fiber'ов), zero-downtime restart через
передачу socket'а, `crails deploy` = scp бинаря + миграции.
Метрика: overhead трейсинга на RPS; время zero-downtime restart;
деплой на чистую VM одной командой.

### Iteration 12 — гигиена 2026
Rate limiting, sandboxed миграции, CSP nonce, secure-by-default
cookies/headers, `crails check` (пассивный анализ безопасности в духе
Brakeman: SQL-интерполяция, небезопасный render и т.п.).

### Iteration 13 — DX: выживание dev-цикла в компилируемом мире
Инкрементальной компиляции в Crystal нет — делаем так, чтобы медленный
full-rebuild не убивал разработку: (1) горячая перезагрузка БЕЗ
рекомпиляции для ECR-шаблонов / i18n / конфигов (рантайм-рендер в dev),
(2) `crails watch`: full rebuild в фоне + подмена бинарника через
zero-downtime restart из Iteration 11 (старт сервера ~10 мс),
(3) человекочитаемые error pages с кодовым контекстом, генераторы.
Метрика: кривая «размер кодовой базы → время rebuild» на rails_hello;
время Ctrl+S→ответ сервера для правки шаблона (цель: <1 c) и правки
кристалл-кода (= время rebuild).

### Iteration 14 — active_backup.cr: встроенный сервис бэкапов
`Active::Backup` (в духе ActiveJob): задачи бэкапа БД (pg_dump),
файлов (ActiveStorage) и логов; сторы-адаптеры: локальный диск / S3 /
FTP / Dropbox / Google Drive; расписание и retention-политики через
recurring jobs (Iteration 7). Цель: приложение на CRails не может
потерять все данные по умолчанию — бэкапы из коробки, настройка из
админки (WordPress-режим).
Метрика: restore-тест в CI — бэкап → подъём приложения на чистой
машине одной командой.

### Iteration 15 — supervision.cr: доступность в духе BEAM (без BEAM)
Изоляцию волокон Erlang переманить нельзя (fiber'ы делят адресное
пространство, падение волокна = падение процесса) — берём границей
OS-процесса, философия «let it crash» на уровне процессов:
- **Роли бинарника:** `crails server|worker|scheduler|supervise` —
  один бинарь, разное поведение. Веб-процесс НИКОГДА не исполняет
  джобы (кроме dev inline-адаптера): упал воркер — веб жив.
- **Супервизор** (`crails supervise`): дети N×web + M×worker,
  перезапуск по падению с backoff; для прода то же умеет systemd,
  встроенный — ради «одной команды на голой VPS».
- **Изоляция внутри процесса:** request/job/ws-соединение — каждое в
  своём волокне под rescue; падение джобы = retry по DSL, не падение
  воркера; circuit breaker на внешние вызовы (LLM API, PSP).
- **Memory watchdog:** RSS > лимита → graceful drain → exit →
  супервизор поднял чистый (утечка не кладёт машину).
Метрика: `kill -9` воркера — веб не заметил (0 ошибок 5xx);
`kill -9` веба — перезапуск < 1 с без потери соединений;
джоба с исключением — retry, процесс жив; RSS-watchdog срабатывает.

## Зависимости-кандидаты (не пишем своё)

- БД: `crystal-pg` (PostgreSQL only в первой итерации).
- Redis: crystal-redis-shard (pubsub для Cable, кэш-стор).
- Крипто: stdlib `OpenSSL`, `Crypto::Bcrypt`, `Random::Secure`.
- HTML-парсер (sanitize/ActionText): lexbor-биндинг.
- Картинки (ActiveStorage variants): libvips биндинг или шелл-аут.
- MIME/SMTP: свой минимальный порт mail-гема (action_mailer.cr).
- YAML/JSON: stdlib.

## Чего НЕ будет (осознанно)

- Zeitwerk/autoload/dev-reload — компилируемый язык; `crails watch` = rebuild.
- Рантайм `constantize` по строкам — только compile-time registry.
- Dynamic finders (`find_by_email`), `with_options`, `StringInquirer`
  (заменён enum-предикатами `CRails.env.production?`).
- Поддержка чужих Ruby-гемов и плагинов, переопределяющих ядро.

## Метрики успеха (замеряем в bench/ на каждой итерации)

- Hello RPS / p99 latency / RSS — vs Rails 8 + Puma (та же машина).
- AR CRUD: чтение/запись RPS при N fibers, ошибки, RSS.
- Джобы/сек (enqueue + perform), latency очереди.
- WebSocket-коннекты до деградации (100k цель), сообщений/сек broadcast.
- Время компиляции, время старта, размер бинарника.
- Честность: одинаковый контекст (один PG, одна машина, warmup).
