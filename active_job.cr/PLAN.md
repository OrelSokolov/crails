# active_job.cr — порт ActiveJob

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActiveJob` — 1:1. Оценка: ~90% (меты почти ноль; один шов —
десериализация класса джобы → compile-time registry).

## API 1:1

### DSL
- `class ProcessJob < ApplicationJob` (`< ActiveJob::Base`),
  `def perform(*args)`
- `queue_as :default` / `queue_as do ... end`; `queue_with_priority N`
- `retry_on Error, wait: 3.seconds, attempts: 5, jitter: 0.15, queue:,
  priority:` (waits: polynomial `:polynomially_longer`; exhausted-блок)
- `discard_on Error`; `after_discard do |job, e| end`
- Коллбэки: `before/after/around_perform`, `before/after/around_enqueue`
- `rescue_from`
- Continuable jobs (8.x): `include ActiveJob::Continuable`,
  `step :name, start:, isolated: do ... end`

### API вызова
- `ProcessJob.perform_later(*args)` (+ блок), `perform_now`,
  `set(queue:, wait:, wait_until:, priority:).perform_later`,
  `perform_all_later(*jobs)` (bulk)
- Инстанс: `retry_job(wait:, queue:)`, `job_id`, `queue_name`,
  `priority`, `arguments`, `executions`, `exception_executions`,
  `scheduled_at`, `provider_job_id`, `successfully_enqueued?`
- Сериализация аргументов: примитивы as-is; Date/Time/Duration/Range/
  NamedTuple через реестр сериалайзеров; **GlobalID** — AR-модель в
  аргументах → `gid://app/User/1`, резолв при выполнении, отсутствующая
  запись → `DeserializationError::RecordNotFound` (типично `discard_on`)
- Locale/timezone переносятся в джобу (I18n.with_locale-обёртка)

### Адаптеры
Интерфейс `enqueue(job) / enqueue_at(job, ts)`: `async` (по умолчанию,
fiber-пул), `inline`, `test`; внешние: PG-очередь (`active_job.cr/adapters/pg`,
skip-locked — кандидат №1 для монолита), Redis-очередь.
`config.active_job.queue_adapter`, per-class `queue_adapter=`.

## Реализация

- `async`-адаптер: очередь `Channel(Job)` + fiber-пул воркеров;
  scheduled-джобы — timer heap (fiber sleep).
- Десериализация `job_class` по строке: compile-time registry
  (`{{ @type.all_subclasses }}` от `ActiveJob::Base`) — все джобы
  известны на компиляции; GlobalID-локатор — тот же registry AR-классов.
- Retry-математика (polynomial backoff `executions**4 + rand*jitter + 2`)
  — статика, 1:1.
- Метрики: `enqueue.active_job` / `perform.active_job` через
  ActiveSupport::Notifications — для bench/.

## Фазы

- P0: Base + perform_later/perform_now + async-адаптер + retry/discard +
  коллбэки + сериализация примитивов.
- P1: GlobalID, PG-адаптер (durable очередь для монолита), scheduled,
  bulk perform_all_later, Continuable.
- P2: test-helpers (`assert_enqueued_with`, perform_enqueued_jobs),
  Redis-адаптер, enqueue_after_transaction_commit.

## Готово, когда

джоба с `retry_on` ретраится с backoff после падения, аргумент-модель
резолвится через GlobalID, а `deliver_later` из action_mailer.cr
работает через эту же очередь.

## Зависимости

active_support.cr, active_record.cr (GlobalID), crystal-pg.
