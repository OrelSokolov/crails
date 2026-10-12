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

## Известные побочные факты

- rails_hello и demo не собираются: в railties require "importmap_cr", а в их
  lib/ нет symlink на importmap.cr (предсуществующее, чинить отдельным заходом).
- Root-файлы (AGENTS.md, PLAN.md, README.md, Rakefile) и ряд шардов имеют
  незакоммиченные изменения — это работа этих фаз, git-мутации не делать.
- middleware_spec в railties — env-зависимые ожидания (в dev стек начинается
  с ViteDevProxy).
