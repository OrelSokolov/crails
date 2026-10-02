# action_mailer.cr — порт ActionMailer

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActionMailer` — 1:1. Оценка: ~80%. Главная скрытая работа —
не DSL, а минимальный порт mail-гема (MIME-сборка + SMTP).

## API 1:1

### DSL
- `class UserMailer < ApplicationMailer` (`ApplicationMailer <
  ActionMailer::Base`; `default from: ...`, `layout "mailer"`)
- `def welcome_email(user); mail(to:, subject:) end` — экшен = метод;
  макрос генерит классовый `UserMailer.welcome_email(user)` →
  MessageDelivery (в Rails это class-level method_missing)
- `.with(user: u).welcome_email` (parameterized)
- `.deliver_now / .deliver_now! / .deliver_later(wait: 5.minutes,
  queue:, priority:) / .message`
- `attachments["x.pdf"] = {mime_type:, content:}`, `attachments.inline`,
  `headers["X-Custom"] = v`
- `mail do |format| format.text { render "x" } format.html { } end`
  (фикс-методы коллектора)
- Коллбэки: `before_action/after_action/around_action`,
  `before_deliver/after_deliver/around_deliver`; `rescue_from`
- Subject через I18n: `user_mailer.welcome_email.subject` — 1:1
- Multipart auto-discovery: `welcome_email.{html,text}.ecr` →
  multipart/alternative
- `register_observer/register_interceptor`
- Previews: `UserMailerPreview < ActionMailer::Preview`,
  `/rails/mailers` dev-страничка (compile-time список preview-классов)
- Delivery methods: `:smtp/:sendmail/:file/:test` +
  `smtp_settings (address/port/user_name/password/enable_starttls_auto/
  openssl_verify_mode/...)`, `raise_delivery_errors`,
  `perform_deliveries`, `deliveries` (test)

### MessageDelivery
Ленивый прокси: `.message`, `.deliver_now/.deliver_later(...)`,
делегация к Mail::Message.

## Реализация

- **mail-port** (`mail/` внутри шарда): MIME-сборка (multipart/alternative,
  mixed, related; quoted-printable/base64; вложения), заголовки,
  SMTP-клиент (STARTTLS/SSL), sendmail-вызов, file-стрелялка.
  RFC 5322/2045/2047 subset, достаточный для 99% транзакционных писем.
- `deliver_later` сериализует имя мейлера+экшен+аргументы в ActiveJob —
  compile-time registry классов мейлеров (список известен при сборке).
- MessageDelivery — явный facade с перечисленными методами
  Mail::Message (без method_missing).

## Фазы

- P0: mail-core (MIME + plain/text/html + вложения), SMTP, DSL
  (`default/layout/mail/deliver_now`), test-метод.
- P1: `deliver_later` (через active_job.cr), parameterized `.with`,
  multipart auto-discovery, inline attachments, observers/interceptors.
- P2: previews, i18n-subject полный, file/sendmail методы.

## Готово, когда

`UserMailer.welcome_email(user).deliver_now` отправляет реальное письмо
через SMTP с multipart/alternative + вложением, а
`.deliver_later` кладёт джобу в очередь.

## Зависимости

active_support.cr, action_view.cr (шаблоны), active_job.cr (P1).
