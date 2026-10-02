# action_mailbox.cr — порт ActionMailbox

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActionMailbox` — 1:1. Оценка: ~85%. Крошечный гем — тонкая
обёртка над Mailer/Storage/Job; берёмся последним из основных.

## API 1:1

- `class ApplicationMailbox < ActionMailbox::Base`:
  `routing address => :mailbox` — address: String / Regex / Proc / :all
- `class RepliesMailbox < ApplicationMailbox; before_processing;
  def process; ...; end` (+ `after/around_processing`, `rescue_from`)
- Инстанс: `inbound_email`, `mail` (Mail::Message),
  `bounce_with(message)` / `bounce_now_with(message)`
- `ActionMailbox::InboundEmail < ActiveRecord::Base`:
  `has_one_attached :raw_email`, enum статусов
  `pending/processing/delivered/failed/bounced`, `#mail`, `#source`,
  `#processed?`; incinerate-джоба (`incinerate_after` 30 дней)
- Ingress HTTP-эндпоинты: `relay` (basic auth + ingress password),
  `postmark/sendgrid/mailgun/mandrill` — контроллеры-приёмники
- Config: `config.action_mailbox.incinerate/incinerate_after/queues/
  ingress/logger`

## Реализация

- Роутинг mailbox-имён: compile-time registry (routing-таблица пишется в
  одном классе — имена известны при сборке).
- Пайплайн: ingress-контроллер → InboundEmail (AR + raw_email blob) →
  ActiveJob-роутинг → mailbox `process` → статус.
- Зависимость от mail-порта action_mailer.cr (парсинг входящих писем).

## Фазы

- P0: InboundEmail-модель + routing DSL + `process` + статусы.
- P1: ingress relay/postmark/sendgrid/mailgun, bounce, incinerate.

## Готово, когда

POST ingress-запрос с RFC822-письмом создаёт InboundEmail и направляет
его в mailbox по routing-правилу.

## Зависимости

active_record.cr, active_storage.cr, action_mailer.cr, active_job.cr.
