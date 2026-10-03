# devise.cr — порт Devise

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `Devise` — 1:1. Оценка: ~80%. Берётся на Iteration 6,
после стабильного active_record/action_pack/action_view. Цель — Rails-приложение
с девайс-аутентификацией переносилось заменой `Rails→CRails`.

## API 1:1

### Модель
- `devise :database_authenticatable, :registerable, :recoverable,
  :rememberable, :trackable, :validatable, :confirmable, :lockable,
  :timeoutable, :omniauthable` (модули включаются макросом — как в
  Rails, где это `devise_modules`)
- `validatable` = стандартные валидации email/пароля (1:1 к active_record.cr)
- `User.create!`, `update_with_password`, `valid_password?`,
  `send_reset_password_instructions`, `confirm`, `lock_access!` и т.д.
  по модулям

### Роуты и контроллеры
- `devise_for :users (path:, controllers:, path_names:, only:, except:)`
  → `/users/sign_in|sign_up|sign_out|password|confirmation` — те же пути
- Sessions/Registrations/Passwords/Confirmations/Unlocks контроллеры
  (сгенерированные, кастомизируются наследованием — как в Rails)
- Хелперы: `authenticate_user!` (before_action), `user_signed_in?`,
  `current_user`, `user_session`, `require_no_authentication`,
  `after_sign_in_path_for`-хуки

### Конфиг и взгляды
- `config/initializers/devise.cr`: `config.mailer_sender`,
  `config.password_length`, `config.remember_for`, `config.timeout_in`,
  `config.maximum_attempts`, `config.unlock_strategy`,
  `config.pepper`, `config.stretches` — те же имена
- `devise :views` — кастомизируемые ECR-вьюхи
- Mailer: `Devise::Mailer` (confirmation/reset — через action_mailer.cr)
- `secret_key` → pepper/peppering паролей как в Rails

### Аутентификация под капотом
Warden-стэк → `HTTP::Handler`-middleware: сессия → стратегия → failure
app. Хэши паролей: `Crypto::Bcrypt` (stdlib) с pepper-подмешиванием,
cost = stretches. Sessions: cookie_store из railties.cr.
Rememberable: signed cookie + токен-таблица.

## Чего не будет в P0

`omniauthable` (внешние провайдеры — P2, нужны OAuth-клиенты),
`saml`, test-helpers (`sign_in user` в тестах — P1), `devise-otp` и
прочие сторонние расширения.

## Статус (Iteration 6 — P0 готов, oracle 26/26 + юниты 11, итого 37/37)

- Оракул: `oracle/cases.rb` → `expected.yml` — standalone-харнесс devise
  4.9.4 (AR sqlite), 26 кейсов, повторный прогон DETERMINISTIC. Зеркало
  `spec/oracle_spec.cr` проходит 26/26 без правки кейсов.
- Модель: макрос `devise` (src/models.cr) на AR::Base — виртуальные
  password/password_confirmation, `valid_password?`,
  `update_with/without_password`, валидации validation__devise_* (AR-раннер),
  uniqueness через `WHERE LOWER(email) = LOWER(?)`, rememberable
  (authenticatable_salt = ep[0,29], serialize_into/from_cookie),
  registerable (перехват new/create/create! с password-до-save).
- Encryptor: bcrypt (stdlib) с pepper, **byte-compatible с gem'ом**
  (Ruby-хэши rehash-ятся идентично; verified). Отклонение: Crystal-bcrypt
  не хэширует ровно 72 байта (внутр. NUL) → обрезаем до 71 (Ruby до 72);
  различается только пароль ровно в 72 байта.
- Sessions (`src/sessions.cr`): Warden-замена — sign_in/out/signed_in?,
  current_user, authenticate + flash-строки devise en.yml. HTTP-интеграция
  (cookie-сессии action_pack) — P1.
- JWT (`src/jwt.cr`, наш модуль — в Rails его нет): HS256 через
  OpenSSL::HMAC, access {sub,iat,exp,jti} + opaque refresh
  (SHA256-хэш в devise_refresh_tokens), ротация с ревоком,
  TokenInvalid/TokenExpired. Кросс-чек: ruby-jwt-токен декодируется
  тем же secret (фикстура в spec).
- Юниты: `spec/sessions_jwt_spec.cr` — 11 кейсов (flash, session store,
  roundtrip, tamper, wrong secret, expired, кросс-декод, ротация+ревок).

**Не в P0 (см. Фазы):** recoverable/confirmable/trackable/lockable/
timeoutable + Devise::Mailer — P1; HTTP-роуты `devise_for`/контроллеры —
P1 (вместе с railties-сессиями); omniauthable — P2.

## Фазы

- P0: database_authenticatable + registerable + validatable +
  rememberable + sessions (sign_in/out, current_user, flash-сообщения),
  bcrypt с pepper.
- P1: recoverable (reset по email), confirmable, trackable, lockable,
  timeoutable, Devise::Mailer.
- P2: omniauthable (Google/GitHub OAuth2), test-helpers, i18n-полный
  (девайс-словари локалей).

## Готово, когда

`devise_for :users` + `before_action :authenticate_user!` дают
рабочий sign_up/sign_in/sign_out/reset-password флоу с теми же URL и
flash-сообщениями, что в Rails.

## Зависимости

active_record.cr, action_pack.cr, action_view.cr, action_mailer.cr,
active_support.cr.
