# План оставшихся фаз (возобновление сессии)

Контекст: докидываем в CRails недостающие части Rails 8.1.4 (таблица пробелов
сайта). Конвенция репо (AGENTS.md): oracle-first — кейсы на оригинальных гемах
(ruby 3.4.5, rails/devise 8.1.4/4.9.4 установлены; строки "case_id\tvalue" в
oracle/*.yml), Crystal-спек зеркально воспроизводит те же case-ID; реверс —
ruby-скрипт oracle/verify_*.rb, вызываемый из спека через Process.run (паттерн:
active_support.cr/spec/crypto_oracle_spec.cr). Подробный общий план:
~/.h2code/sessions (план фаз A–I утверждён пользователем).

## Статус

- [x] Фаза B — railties.cr credentials — ГОТОВО (2026-10-05): оракул
      7 кейсов + фикстуры (реальный EncryptedFile 8.1.4, pinned-ключ),
      реверс verify_credentials.rb; CRails::EncryptedConfiguration
      (MarshalStringCodec — единственный срез Marshal: UTF-8 строки),
      wire aes-128-gcm + 3 части b64(iv)--ct--tag; для этого
      active_support.cr MessageEncryptor AEAD параметризован шифром
      (был баг: EVP захардкожен aes-256-gcm); CLI credentials:show/edit
      + secret; генератор master.key/credentials.yml.enc/.gitignore;
      `CRails.root=` тестовый хук. Спек 11/11, сюит railties 185/185,
      active_support 319/319. Детали: railties.cr/PLAN.md Iteration 12.
- [x] Фаза E — action_cable.cr stream_for/broadcast_to — ГОТОВО
      (2026-10-05): broadcasting_for = [channel_name,
      to_gid_param].join(":"), gid = base64url без паддинга от
      "gid://<app>/<Class>/<id>"; connection: request/cookies/session,
      reject_unauthorized_connection! → disconnect-фрейм. Спек 11/11,
      сюит 51/51. Детали: action_cable.cr/PLAN.md.
- [x] Фаза H — devise.cr HTTP-слой — ГОТОВО (2026-10-05): оракул 74
      кейса с devise 4.9.4 на rails 8.1.4 (регистрация 303/422-wrong-pw
      responder.error_status, warden-ключ session, remember-cookie,
      omniauth passthru 404); роуты devise_for 1:1, контроллеры
      Sessions/Registrations/Passwords/Confirmations/Unlocks/
      OmniauthCallbacks, вьюхи + Devise::ViewsGenerator, Proc-хуки
      моделей через кодген (главный Crystal-паттерн). confirmation_token
      — raw в БД (unlock_token — digest), соль = encrypted_password[0,29].
      Спек 16/16, сюит devise 120/120. Детали: devise.cr/PLAN.md Phase H.
- [x] Фаза P2 devise — GitHub-провайдер + test-helpers + i18n-полный —
      ГОТОВО (2026-10-06): GitHub (omniauth-github 2.0.1 вендорен,
      оракул gh_* 12 кейсов: client_options/scope/state/AuthHash c
      /user/emails и all_emails+scope в extra; Devise::OmniAuth::GitHub +
      интерфейс Strategy + register_github, зеркало 39/39 c wire-flow);
      test-helpers (Devise::Test::IntegrationHelpers: оракул th_* 14 кейсов
      с devise 4.9.4+warden 1.2.9, sign_in/sign_out → warden-ключ сессии);
      i18n (en.yml гема 1:1 в src/locales, compile-time read_file;
      Devise.t/t! c ресурс-префикс-фоллбеком, интерполяцией и one/other;
      Devise.load_locale/locale=; все flash/failure/mailer-строки через
      t!; оракул i18n_* 15 кейсов incl. ru-локаль). Сюит devise 145/145.
      Детали: devise.cr/PLAN.md «P2 — GitHub + test-helpers + i18n».
- [x] CSP/secure-headers (railties.cr) — ГОТОВО (2026-10-05): оракул
      14 кейсов (default headers Rails 8.1: X-Frame-Options SAMEORIGIN,
      nosniff, Referrer-Policy strict-origin-when-cross-origin и др.;
      CSP из блок-DSL, маппинг символов, report-only); CRails::
      ContentSecurityPolicy (MAPPINGS/DIRECTIVES 1:1) + middleware в
      дефолтном стеке до ShowExceptions (404/500 тоже получают
      заголовки); crails new пишет config/initializers/
      content_security_policy.cr. Спек 5/5, railties 185/185.
      Детали: railties.cr/PLAN.md Iteration 13.
- [x] HTTP caching fresh_when/etag (action_pack.cr) — ГОТОВО
      (2026-10-05): оракул 20 кейсов (weak/strong ETag = W/"sha256[0,32]",
      304 по If-None-Match/If-Modified-Since, strict_freshness —
      дефолт Rails 8.1: If-None-Match перекрывает If-Modified-Since;
      Cache-Control public / max-age=0,private,must-revalidate);
      fresh_when/stale? в ActionController::Base. ActionController::Live/
      SSE не портированы — в demo не используются (live = WS LiveView,
      turbo_stream_from = ActionCable). Спек 8/8, action_pack 99/99
      (`make spec`, CRAILS_VIEWS). Детали: action_pack.cr/PLAN.md
      Iteration 15.
- [x] Роли процессов (railties.cr) — ГОТОВО (2026-10-05): boot
      worker/scheduler (хуки CRails.application.worker/scheduler по
      образцу bot_poller; exit 3 = роль не скомпилирована),
      `crails supervise` — супервизор Procfile-ролей (рестарт с backoff
      1→2→5s, exit-3 роли отключаются, TERM-шатдаун), Procfile в
      `crails new`. Спек 2/2, railties 185/185. Детали:
      railties.cr/PLAN.md Iteration 14.
- [x] Фаза G — active_record.cr encryption — ГОТОВО (2026-10-05):
      оракул 26 кейсов (enc_*, activerecord 8.1.4 standalone, pinned-ключи)
      + реверс verify_encryption.rb; src/encryption.cr (Aes256Gcm EVP,
      deterministic iv = HMAC-SHA256[0,12], MessageSerializer JSON
      {"p":..,"h":{"iv":..,"at":..[,"c":true]}} побайтово, компрессия zlib
      >140 байт, DerivedSecretKeyProvider PBKDF2-SHA1 2**16); encrypts-макрос
      (геттер decrypt / сеттер encrypt, read_row напрямую в ivar) +
      where_encrypted; ENV ACTIVE_RECORD_ENCRYPTION_* fallback.
      Спек 20/20, сюит active_record 283/283. Детали:
      active_record.cr/PLAN.md (Encryption).

- [x] Iteration 14 (Фаза 3) — active_backup.cr — ГОТОВО (2026-10-06):
      бэкапы БД/файлов (tar.gz: ustar+gzip, GNU-tar-совместимо; db.dump
      pg_dump -Fc; manifest.json последним, sha256 членов) + сторы-порт
      Local/Memory + retention keep_last/keep_days + BackupJob (recurring
      через ActiveJob) + restore-тест в CI (бэкап → DROP DATABASE/rm -rf →
      restore → побайтовая сверка; порча байта ловится). Сюита 18/18,
      бенч results/205-backup.md. Детали: active_backup.cr/PLAN.md,
      корневой PLAN.md (Iteration 14 Фазы 3).

- [ ] Интеграция оригинального @rails/actioncable (клиентский слой) —
      TODO: заменить самодельный WS-слой demo
      (app/assets/javascripts/turbo_cable.js, ~60 строк — «аналог
      cable.js из @hotwired/turbo-rails») на vendored UMD-сборку
      оригинального @rails/actioncable (consumer/subscriptions) для
      полного соответствия интерфейсу turbo-rails: control-фреймы
      (welcome/ping/disconnect/confirm_subscription) обязан съедать
      библиотечный слой, а не ручная проверка frame.type (костыль из
      251d368: пока её не было, epoch-ms из ping-фреймов рендерились
      в <body> через Turbo.renderStreamMessage). Вместе с этим —
      пересмотр interfaces: stream-source элемент, identifier
      протокол, reconnect-семантика actioncable; оракул —
      побайтовое/поведенческое сравнение с turbo-rails 8.1.x в
      headless-браузере. Затрагивает: demo, turbo.cr (PLAN.md P1:
      повтор E2E), возможно railties.cr (раздача vendored JS).
- [ ] Chat: инлайн WS-клиент на actioncable consumer — TODO: второй
      самодельный ActionCable-клиент живёт в page_js вьюхи
      (demo/app/views/chat/index.html.erb:44-53): сам говорит на
      протоколе (subscribe/message), сам фильтрует фреймы (от ping
      спасает случайно — у ping нет msg.text). Перевести на consumer
      из @rails/actioncable вместе с turbo_cable.js (пункт выше).
- [ ] Demo: вычистить протухшие «известные упрощения» (README) —
      TODO-аудит:
      * `post /notes/:id/destroy` → честный DELETE-роут: README
        утверждает «нет _method-override», но он уже есть —
        railties.cr/src/middleware.cr:382 request_method (аналог
        Rack::MethodOverride, поддерживает PATCH/PUT/DELETE);
        обновить роут, форму (button_to method: :delete) и README;
      * `render_action("new", 422)` (ApplicationController) — костыль
        вместо `render :new, status:`: implicit render знает только
        текущий экшен; дорастить action_pack до render другого
        шаблона того же контроллера;
      * `CableValue` рекурсивный алиас: броадкасты бота уходят через
        JSON.parse (demo/src/cable.cr) — литералы не инферятся в
        рекурсивный union;
      * data-confirm только Hash-формой (`data: {"confirm" => ...}`):
        NamedTuple-литерал в **opts не кастится в Hash(String,String).
- [ ] Devise: layout-типизация current_user — TODO: убрать
      `current_user.as?(User)` из demo-layout
      (application.html.erb:249): devise-хелперы включены прямо в
      ActionController::Base, и framework-контроллеры видят
      current_user : ActiveRecord::Base+? без методов модели, а layout
      компилируется в контексте каждого контроллера. Как в Rails:
      devise-контроллеры должны наследовать ApplicationController
      приложения (parent_controller-механика devise), тогда layout
      видит типизированный current_user.
- [ ] GlobalID-сериализация AR-записей в ActiveJob — TODO: убрать
      ArgValue-костыль `__record_email(record : ActiveJob::ArgValue)`
      в devise.cr/src/mailer.cr: он нужен потому, что action_mailer's
      __deliver-кодген инстанцирует экшены мейлера сериализованными
      аргументами, а AR-записи в ArgValue не входят (нет GlobalID —
      to_arg на них падает). Порт GlobalID (gid://model/id) даст
      record'у пережить deliver_later и уберёт оверлоад.
- [ ] Demo: убрать дублирование раздачи ассетов — TODO: AssetsController
      фактически мёртв (static-middleware перехватывает /assets/* по
      propshaft до роутера); оставить один механизм раздачи.
- [ ] Demo: bootstrap lib/-симлинков — TODO: demo/lib в .gitignore,
      symlink'и ставятся руками; свежий клон падает на сборке
      («can't find propshaft_cr» — то, что уронило demo 2026-10-15).
      bin/crails должен бутстрапить lib/ по зависимостям shard.yml
      (как `shards install`, но на локальные ../<shard>.cr).

Сводные сюиты (2026-10-05): railties 185/185, action_pack 99/99,
active_support 319/319, active_record 283/283, devise 120/120,
action_cable 51/51. Фазы A–I закрыты полностью.

После каждой фазы: `crystal spec` шарда зелёный; в конце — прогон всех
затронутых шардов. Постгрес: postgres://root@/crails_<shard>_test?host=/var/run/postgresql.
Пользователь просил фазы делать самому (без фоновых агентов).

## Фаза C — cookies.signed/encrypted (action_pack.cr) — ЗАВЕРШЕНА

Реализовано полностью; детали — action_pack.cr/PLAN.md (Iteration 14).
Ключевые факты (уточнённые, supersede заметки ниже):

- legacy-конверт {"_rails":{"message":strict_b64(json),"exp":..,"pur":..}}
  + SHA1 — это и ЕСТЬ wire-формат приложения (verifier/encryptor cookies
  использует NullSerializer, который не входит в Metadata::
  ENVELOPE_SERIALIZERS → `use_message_serializer_for_metadata` на cookies
  не действует; проверено снятием оракула с флагом — вывод идентичен).
  Предыдущая посылка плана «приложение пишет data-конверт» была неверна.
- MessageVerifier/Encryptor получили опции `digest:` (sha1/sha256),
  Bytes-секрет и `force_legacy_metadata_serializer:` (active_support.cr,
  Iteration 9); cookies их используют → ck_signed_* побайтово совпадают.
- API: cookies.set(name, value, expires:/path:/domain:/secure:/httponly:/
  same_site:), cookies.signed/encrypted/permanent (+ .permanent.signed),
  delete(name, path:, domain:); ActionController.cookies_secret_key_base=
  / ENV["SECRET_KEY_BASE"]; session/flash подписаны при секрете, читают
  оба формата (legacy fallback), пишут legacy Base64-JSON без секрета.
- Оракул: oracle/cookies_cases.rb + cookies_expected.yml (fixed salt/
  secret, iterations 1000; ck_encrypted_fixture_* — random-IV фикстры,
  decrypt-направление), реверс oracle/verify_cookies.rb (гем читает
  cookies порта через настоящие jar'ы actionpack). Спек
  spec/cookies_oracle_spec.cr 33/33, сюит 91/91.

## Фаза B — Credentials (railties.cr) — ЗАВЕРШЕНА (2026-10-05)

Реализовано полностью; детали — railties.cr/PLAN.md (Iteration 12).
Уточнение против плана ниже: cipher = aes-128-gcm (EncryptedFile::CIPHER),
wire = legacy 3 части strict-b64 iv--ct--tag, внутри Marshal.dump(String).

## Фаза G — ActiveRecord Encryption (active_record.cr) — ЗАВЕРШЕНА (2026-10-05)

Детали — active_record.cr/PLAN.md (Encryption). Исходный план ниже.

Исходники: activerecord-8.1.4/lib/active_record/encryption/{encryptor.rb,
cipher/aes256_gcm.rb, message.rb, scheme.rb, key_providers/
derived_secret_key_provider.rb, properties.rb, config.rb},
attribute_methods/encryption.rb.
- deterministic: true — ПОБАЙТОВО: iv выводится из ключа+plaintext (см.
  deterministic-ветку Aes256Gcm). Message-формат для колонки — снять оракулом.
- Ключи: config primary_key/deterministic_key/key_derivation_salt; derive от
  secret_key_base если не заданы; ENV (AR_ENCRYPTION_* — сверить с гемом).
- API: макрос `encrypts :attr, deterministic:` (генерация кода, как валидации
  шарда); геттер расшифровывает (nil-safe, голая строка → как есть), сеттер
  шифрует; поиск по deterministic — если where-врезка сложна, сделать
  `where_encrypted(attr, value)` + отклонение в доке.
1. Оракул oracle/encryption_cases.rb → oracle/encryption_expected.yml (enc_*):
   activerecord standalone (require "active_record"; configure с фикс.
   ключами; sqlite в памяти): deterministic побайтово, non-deterministic —
   decrypt-направление, roundtrip, NULL, where. Реверс
   oracle/verify_encryption.rb.
2. src/encryption.cr (+require в зонтичный src). Encryptor, Cipher::Aes256Gcm
   (+deterministic iv), Message+serializer, DerivedSecretKeyProvider, Scheme,
   Properties, макрос encrypts.
3. spec/encryption_oracle_spec.cr (реплей + реверс + postgres-юниты) + PLAN.md.

## Фаза E — ActionCable identified_by + stream_for — ЗАВЕРШЕНА (2026-10-05)

Детали — action_cable.cr/PLAN.md. Исходный план ниже.

- src/connection.cr: `identified_by :current_user` (macro, список
  identifiers), хуки connect/disconnect, reject_unauthorized_connection!,
  доступ к request.cookies (заголовки upgrade-запроса) → верификация сессионной
  cookie фазы C (ActionController.cookies_secret_key_base / подписанный
  crails_session) → current_user. connection_identifiers → в подписки.
- src/channel.cr: stream_for(record)/broadcast_to(record, payload);
  broadcasting_for = [channel_name, model.to_param].join(":") — точный формат
  ([channel_name, to_gid_param || to_s].join(":")) снять оракулом с
  actioncable 8.1.4.
- Оракул: broadcasting_for-имена (кейсы с AR-моделью), идентификаторы коннекта,
  протокольные сообщения. Спек: FakeConnection + ws-стиль существующих спеков.

## Фаза H — Devise HTTP-слой — ЗАВЕРШЕНА (2026-10-05)

Детали — devise.cr/PLAN.md (Phase H). Исходный план ниже.

Модельная часть готова (все 10 модулей, byte-совместимые токены; sessions.cr —
in-memory заглушка). HTTP нет вовсе; shard.yml НЕ зависит от action_pack.

1. shard.yml += action_pack_cr, action_view_cr (path).
2. Роутинг: `devise_for :users` в CRails::Routes drawer — стандартная таблица
   devise (sessions/registrations/passwords/confirmations/unlocks/
   omniauth_callbacks по модулям модели), devise_scope.
3. Warden-lite: сессия в ActionController::Session, ключ
   "warden.user.<scope>.key"; rememberable через cookies.permanent.signed
   ("remember_<scope>_token", serialize_into/from_cookie — модель готова);
   helpers: current_user, user_signed_in?, authenticate_user!,
   require_no_authentication, after_sign_in_path_for (stored location).
4. Контроллеры (наследуемые, before_action-хуки как в devise, sanitizer
   параметров): Sessions (new/create/destroy), Registrations
   (new/create/edit/update/destroy), Passwords (new/create/edit/update),
   Confirmations, Unlocks, OmniAuthCallbacks (+ request-phase /auth/:provider
   → Google authorize_url из omniauth.cr, callback → from_omniauth).
5. Вьюхи: минимальные дефолтные (генератор `crails g devise:views`), контроллеры
   работают и без них (редиректы/JSON).
6. Оракул: devise 4.9.4 в throwaway rails-приложении (tmp/): вывод `rails
   routes`, session-ключи, имена cookie, flash-ключи, редирект-путей, 401
   → oracle/expected_http.yml. Интеграционный спек: register → login →
   logout → password reset (postgres, fake-контроллеры через __set_params/
   __run_action — паттерн action_pack.cr/spec/controllers_spec.cr).

## Фаза AM — порт ActiveModel 8.1.4 + рефакторинг компонентов — ПЛАН

Шард `~/myshards/active_model.cr` (план: `~/myshards/active_model.cr/PLAN.md`):
перенос единственного из 11 гемов rails/rails без порта. Oracle-first по
AGENTS.md (cases.rb + test-suite гема activemodel 8.1.4, локально в rvm).
Высветлить из active_record.cr валидации/Errors/dirty/callbacks-машину;
AR включает AM (как в оригинале). Интеграция: devise (validatable на
AM-валидаторах вместо рукописных errors.add), active_storage/action_text
(AM::Naming-контракт), action_view (form objects через AM::Model).
Критерий: все существующие сюиты AR/devise зелёные без правок; публичные
API не меняются. Репозиторий/README — после реализации (итерация 5 плана).

## Фаза CF — Campfire 1:1 (полный продукт на CRails) — ПЛАН

Контекст: целевое приложение `~/workspace/once-campfire-crails` — реализация
ONCE Campfire на CRails, собранная как бенчмарк-срез (только 8 контрактных
роутов + browser gate). Цель — довести до полного продукта, перенося
Rails-реализацию максимально 1:1. Оракул-референс:
`~/workspace/once-campfire-crails/bench-workspace/once-campfire` (rev edbc779,
оптимизированная; для продуктовых фич — первоисточник). Вторичный референс
«нерельсовый стек уже прошёл этот путь»:
`bench-workspace/once-campfire-express` — там ВСЁ из перечисленного ниже уже
реализовано (membership-чеки, Origin/Sec-Fetch-Site, sanitize-html,
rate limit, бусты, аттачи с вариантами, web push, opengraph, все каналы,
refresh-протокол) — сверяться при порте.

Аудит приложения (2026-10-15, сессия H2Code): приложение обходит шарды —
raw SQL вместо associations, HTML строками вместо вьюх, свой JobQueue вместо
ActiveJob, свой PageCache. Реальные дыры: membership не проверяется на HTTP-путях
(IDOR: чтение/запись/переименование любой комнаты), нет Origin/Sec-Fetch-Site
чека на не-GET, stored-XSS через тело сообщения (body рендерится как есть),
FTS-краш (`q=AND` → fts5 syntax error → 500; Rails квотит слова —
`message/searchable.rb` `match_terms`). Отсутствуют: бусты, аттачи, удаления
(сообщений/комнат/sign-out), opengraph unfurl, звуки, typing, read/unread live
(unread fanout и `user_X_reads` бродкасты мертвы), refresh-протокол (стаб),
involvement, баны, полный bot JSON API, `/users/:id` (ссылки из сообщений — 404),
история поиска, `?after=`, запись last_room, permalink `@:messageId`.

Этапы (каждый: oracle-first по AGENTS.md → `crystal spec` шарда зелёный →
browser smoke + verification harness приложения не краснеют):

- [x] CF-0.1 header_only forgery protection — ГОТОВО (2026-10-15):
      action_pack.cr/src/request_forgery_protection.cr + слой rails/rails@main
      (8.2.0.alpha): `using: :header_only|:header_or_legacy_token`
      (forgery_protection_verification_strategy), таблица истинности
      verified_via_header_only?/verified_with_legacy_token? (same-origin/
      same-site ок; cross-site — только trusted_origins; нет хедера — plain
      HTTP фоллбэк по X-Forwarded-Proto; "none" — отказ), QUERY-exempt,
      Vary: Sec-Fetch-Site послеэкшен, if:/unless: в protect_from_forgery,
      InvalidAuthenticityToken → подкласс InvalidCrossOriginRequest (8.2
      алиас-семантика, 8.1.4-зеркало не сломано). 8.1.4-оракула стратегий
      нет — оракул исходник rails@main, спек-зеркало
      railties.cr/spec/csrf_spec.cr describe "verification strategies"
      (17 кейсов; сюит csrf 45/45, railties 336/339 — 3 падения
      предсуществующие, проверено подменой на HEAD-версию файла).
      Осталось (закрыто 2026-10-15): вендоренные lib/*_cr пересинхронизированы
      с myshards (перестройка 13:57), `crystal build src/app.cr --release
      -Dwithout_mt` зелёный (только deprecation-варнинги), browser smoke
      (playwright 1.63, свежая пустая БД из схемы сида, serverX×1) —
      полный PASS.

- [x] CF-0.2 on_subscribe/on_unsubscribe — ГОТОВО (2026-10-15):
      lib/action_cable_cr/src/channel.cr (вендоренная копия — myshards/
      action_cable.cr сейчас висячий симлинк, восстановить при пересинх-
      роне): макросы on_subscribe/on_unsubscribe (метод или блок,
      if:/unless: условия), реестр + end-of-program codegen по образцу
      periodically, выполнение ПОСЛЕ хуков subscribed/unsubscribed
      (гем: after-callbacks). Спек-зеркало
      lib/action_cable_cr/spec/on_subscribe_spec.cr (4 кейса: порядок,
      unless при reject, блочная форма, dispatch как action — Campfire
      refresh). 4/4 + periodically 5/5 (без регресса). Применение:
      PresenceChannel present/absent (unread_at=NULL при present +
      broadcast user_X_reads) — в CF-4.

### CF-0. Точечные фиксы существующих шардов

- action_pack.cr / request_forgery_protection.cr: семантика Rails `header_only`
  (Sec-Fetch-Site + Origin на не-GET, `with: :exception`), включена в
  ApplicationController по умолчанию. Сейчас `forgery_protection_origin_check =
  false` (выключено) — паритет с Campfire `authentication.rb`.
- action_pack.cr / rate_limiting.cr: паритет `rate_limit to:, within:, with:`
  (Campfire: sessions#create, 10/3 мин per IP), общий стор для fork-воркеров
  (образец — express rate_limit.js, отдельная SQLite-таблица).
- action_pack.cr / strong_parameters.cr: убедиться, что require/permit реально
  фильтруют (приложение сейчас достаёт params руками, у Rails — permit!).
- active_record.cr: STI — полные имена классов в колонке type
  («Rooms::Open», не «Open»; приложение сейчас хранит короткие — расходится с
  сидом Rails) + `becomes!`.
- active_record.cr / relation.cr: includes/preload с вложенными хешами
  (`preload(creator: :avatar_attachment)` — сигнатура сейчас принимает только
  плоские `*names`); polymorphic/through сейчас ленивые — для 1:1 нужен nested
  preload. + `insert_all` (Room#grant_to), сверка
  `has_many :through` + `dependent: :destroy` с message/broadcasts.rb.
- action_cable.cr / channel.cr: `on_subscribe :present / on_unsubscribe
  :absent, unless: :subscription_rejected?` (Rails 7.2 API, PresenceChannel
  Campfire на нём построен; сейчас только periodically).
- turbo.cr: полная матрица broadcast_*_to (`partial:`, `target:`, `html:`,
  `attributes: { maintain_scroll: true }` — Campfire использует).
- active_job.cr: перевести приложение с собственного JobQueue на ActiveJob +
  solid_queue-адаптер (он есть), форк-безопасность (reset! после fork — сейчас
  app-level workaround) — в адаптер.

### CF-1. HTML-санитайзер — новый шард rails_html_sanitizer.cr — ГОТОВО (2026-10-15)

`~/workspace/myshards/rails_html_sanitizer.cr` (симлинк в ~/workspace/
crails): порт rails-html-sanitizer 1.7.1, HTML5-vendor (как выбирает
best_supported_vendor Rails 8.1.4), поверх lexbor (с 2026-10-15; изначально
myhtml — см. миграцию в CF-2 ниже).
Oracle-first по AGENTS.md: оракул 57 кейсов с гема 1.7.1 + nokogiri/
gumbo — гемы локально в oracle/gems (rvm-рубины на машине выпотрошены,
оракул ходит системным ruby 3.3.8 с GEM_HOME=oracle/gems); спек-зеркало
9/9, байт-в-байт. API 1:1: Full/Link/SafeList санитайзеры + Permit/
Target/TextOnly скрабберы (strip bottom-up / prune top-down, foreign
svg/math прунится, комментарии снимаются), Loofah-семантика allowed_uri?
(контроль-символы до/после entity-декода, numeric refs без `;`,
&Tab;/&NewLine;/&colon;, %3A-разделитель, 26 протоколов, data:-URI
mediatype-фильтр), опции tags:/attributes: + class-level allowlist'ы.
Ключевое: lexbor/myhtml без fragment-режима — вход парсится как
`<div>#{html}</div>` (body-подобный контекст вставки, «утёкшие» за
лишний </div> узлы подхватываются сиблингами обёртки с сохранением
порядка); сериализатор свой, gumbo-совместимый (&<> nbsp в тексте,
&"nbsp в атрибутах, void-теги, raw-text элементы); обход с мутациями —
next сиблинг захватывается ДО рекурсии. Отклонения (задокументированы в
PLAN.md шарда): CSS-скраба нет (разрешённый style удаляется целиком),
SVG local-ref атрибуты удаляются, а не переписываются, HTML4 = алиасы
HTML5. Вендоринг в lib/ приложения — на CF-4, когда Campfire начнёт
использовать (CF-2 action_text зависит от этого шарда).

### CF-2. action_text.cr — 2a/2b/2c/2d ГОТОВО (2026-10-15)

Готово в 2a/2b (шард `myshards/action_text.cr`, коммит 21d17c1, спеки
только `--release` — см. ниже): Fragment (wrap/source/replace/find_all),
PlainTextConversion, Content canonicalization (minify + trix-conversion,
to_plain_text/to_html), Attachment (from_attachable/from_attributes/
from_node, full_attributes, with_full_attributes, to_html) +
TrixConversion + Minification, Attachable-миксин + Identification-
интерфейс + Attachables::{ContentAttachment,RemoteImage,
MissingAttachable}, SignedGlobalID (Marshal-конверт через новый
`MessageVerifier.generate_marshaled` — active_support cb06ae7; ключ
PBKDF2-SHA1(1000)/"signed_global_ids"). Locator-реестр вместо
constantize. Oracle 42 кейса байт-в-байт (6 групп), детерминирован.
Санитайзер мигрирован myhtml→lexbor 3.6.4 (0b51a49): оба шарда теперь
на живом C-парсере lexborisov, оракулы не изменились. СВЯЗКА ВРЕМЕННАЯ:
C-биндинг будет удалён — в разработке собственный HTML5-парсер на чистом
Crystal (шард с оракулом), выйдет как **html5.cr** и станет целью
миграции; нового кода на lexbor-API поверх Fragment-абстракции не писать.
CAVEAT: debug-сборка (без --release) ловит heap-corruption SIGSEGV в
Attachment-группе — компиляторный артефакт (1.21.1 и 1.22.0, обе
HTML-либы, GC не при чём), детали в PLAN.md шарда.

Остаток CF-2:

- **CF-2c ГОТОВО (2026-10-15, коммит 6f803b0)**: RichText-модель
  (body-кодер руками: dump = Content#to_html, load = Content.new —
  кастомных serialize-кодеров у AR-cr нет; touch владельца в after_save)
  + has_rich_text-макрос на ActiveRecord::Base (ручной where-getter —
  полиморфного has_one у AR-cr нет; autosave after_save; dependent
  before_destroy; POLY_OWNERS через has_many as_name:). Оракул
  cases_ar.rb 26 кейсов, спек 26/26 байт-в-байт (sqlite). Wire-факт:
  body хранится несанитизированным — санитайз при рендере (CF-2d).
  ДЕПО: найден и задокументирован мискомпайл компилятора — module-union
  портится на границе конструктора Attachment (COMPILER_BUG_REPORT.md,
  repro/union_miscompile/, Crystal 1.20.1–1.22.0); спеки шарда гонять
  ПОФАЙЛОВО (комбинированный бинарь ловит баг). При встройке шарда в
  приложение (CF-4) баг может проявиться — тогда репро/отчёт уже готовы
  для upstream, либо снимается приходом html5.cr.
  ПОДВОХ: active_record.cr/shard.yml локально указывает
  active_support_cr как path ../active_support.cr (для резолва
  path-цепочки action_text.cr) — НЕ коммитить, откатить перед
  публикацией AR-шарда.
- **CF-2d ГОТОВО (2026-10-15)**: AttachmentGallery (селектор гема
  `div:has(gallery + gallery)` воспроизведён обходом: все дети —
  ws-текст/gallery-аттач + пара соседних ЭЛЕМЕНТ-детей), ContentHelper
  (render_action_text_content/_attachments/_attachment, санитайз
  HTML5-вендора — дефолт Rails 8.1; вместо ActionView — реестр
  register_attachment_renderer, дефолты — побайтовые порты ERB-вьюх
  гема: missing ☒, content_attachment, remote_image, gallery-layout,
  layout div.trix-content), Content#to_s = layout-рендер (to_html —
  сырое тело для БД), Content::Filter/Filters (пайплайн Campfire
  rails_ext, canonicalize: false), Selector value-формы `[attr=v]` /
  `[@attr='v']`. Эффективная семантика гема снята оракулом (gallery-
  check в render_attachments мёртв — все аттачи через with_full_
  attributes-rebuild + inner_html-рендер, content-атрибут санитизируется
  и дропается если пуст). Оракул +29 кейсов (ag_*/rd_*/flt_*: 63 всего,
  рендер — настоящими вьюхами гема через ActionController-renderer),
  спек 9/9 байт-в-байт + AR 26/26. НАЙДЕН ВОРКАРАУНД мискомпайла
  module-union: union НЕ должен проходить аргументом ни в один
  конструктор — Attachment#initialize принимает только node, @attachable
  присваивается сеттером; репро stage.cr теперь зелёное (регрессионный
  страж), детали COMPILER_BUG_REPORT.md/PLAN.md шарда. Обход
  action_text_each_descendant исправлен на document-order (был
  LIFO-реверс). Остаток CF-2 — нет (вендоринг в lib/ приложения — при
  встройке на CF-4).

### CF-3. active_storage.cr — ГОТОВО (2026-10-15, myshards/active_storage.cr: 6e6030d/b60d7ae/51531fe/ced49c9)

Oracle-first по AGENTS.md: oracle/cases.rb гоняет activestorage 8.1.4
standalone (70 детерминированных кейсов), spec/oracle_spec.cr — зеркало,
71/71 побайтово. 3a Blob core (checksum, signed_id SHA1+Marshal-int,
identify срезом Marcel, DiskService) → 3b Attachment + Attached::One/
Many + has_one/many_attached (POLY_OWNERS-реестр AR-cr) → 3c Variation/
Variant/NamedVariant (digest/key через Marshal-wire, ImageMagick 7 CLI —
снято с mini_magick: `IN[0] -auto-orient -resize WxH> fmt:-`) → 3d
analysis (`identify`, EXIF-swap) + purge. Отклонения и wire-факты —
PLAN.md шарда. Остаток: URL-generation (routes гема) не портировалась —
в Campfire отдаётся контроллером приложения; VariantWithRecord/
track_variants — гем-дефолт false.
Blob/Attachment/VariantRecord, Disk-сервис, `has_one_attached`/
`has_many_attached`, варианты (avatar_variant → webp), analysis, signed_id
прямых загрузок, purge-джобы. Oracle: activestorage 8.1.4.
ГЛАВНЫЙ ТЕХНИЧЕСКИЙ РИСК фазы: image-бэкенд в Crystal (аналога sharp нет) —
решить заранее: binding к libvips или ImageMagick (системная зависимость!)
или минимальный свой ресайзер. Эксплойт-поведение Campfire: аватары
(`users/avatar.rb`), аттачи сообщений с превью, логотип аккаунта.

### CF-4. Порта приложения 1:1 (~/workspace/once-campfire-crails)

- Вьюхи: ERB→ECR конвертер (по образцу nunjucks-to-eta у express) или
  расширение compile_partials для чтения файлов без ручных locals; форматные
  шаблоны `.turbo_stream` (create/update/destroy сообщений) и JSON
  (jbuilder для bot API). ~100 вьюх референса.
- Контроллеры/каналы/джобы — из референса 1:1 (concerns RoomScoped/
  Authorization/Authentication, все каналы, включая TypingNotifications и
  ReadRooms; jobs: broadcast_unread_room, push_message, bot/webhook,
  remove_banned_content, room/destroy).
- Замена raw SQL → associations/scopes, string-HTML → вьюхи, JobQueue →
  ActiveJob, PageCache → app-level ResponseCache/FragmentCache/RecordCache
  (в оптимизированном Rails это МОДЕЛИ приложения — портируются 1:1, шардами
  не являются).
- Чек-лист паритета (из аудита): бусты, аттачи, баны, unfurl, звуки, typing,
  read/unread live, refresh-протокол, involvement, полный bot API (X-Total-Count
  / Link-пагинация), sign-out, `/users/:id`, история поиска + clear, `?after=`,
  `@:messageId`, запись last_room, join_code-регенерация, логотип, управление
  юзерами аккаунта, PWA, sounds.

### CF-5. Web Push (опционально, после CF-4)

VAPID (JWT ES256) + aes128gcm — готового шарда нет, писать поверх openssl.
Референс: express jobs.js:353-397 (web-push), Campfire push.rb.

Порядок: CF-0 → CF-1 → CF-2 → CF-3 (решение по image-бэкенду принять на
старте CF-3) → CF-4 → CF-5. Синхронизация: приложение вендорит копии шардов
в lib/*_cr (имена отличаются от myshards!) — после каждого этапа переливка
myshards → lib/ отдельным заходом.

## Известные побочные факты

- rails_hello и demo не собираются: в railties require "importmap_cr", а в их
  lib/ нет symlink на importmap.cr (предсуществующее, чинить отдельным заходом).
- Root-файлы (AGENTS.md, PLAN.md, README.md, Rakefile) и ряд шардов имеют
  незакоммиченные изменения — это работа этих фаз, git-мутации не делать.
- middleware_spec в railties — env-зависимые ожидания (в dev стек начинается
  с ViteDevProxy).
