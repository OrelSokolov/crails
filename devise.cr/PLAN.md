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
