# CRails — Crystal on Rails

> ⚠️ **EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.**
> Это эксперимент. Мы замеряем производительность и смотрим, что
> получится на данный момент. Никаких гарантий совместимости.

## Что это

Полный клон API Ruby on Rails на Crystal, максимально 1:1 по конечному
интерфейсу — чтобы разработчик, перешедший с Ruby/Rails, не почувствовал
разницы. Цель: код Rails-приложения переносится на Crystal почти дословно.

**Единственное отличие неймспейса: `CRails` вместо `Rails`.**

- `CRails.application`, `CRails.env`, `CRails.root`, `CRails.logger` — так,
  как в Rails было `Rails.*`.
- `ActiveRecord::Base`, `ActiveSupport::Concern`, `ActionController::Base`,
  `ActionView::FormBuilder`, `ActionCable::Channel::Base`, `ActiveJob::Base`,
  `ActiveStorage::Blob`, `ActionMailer::Base`, `ActionText`, `ActionMailbox` —
  имена модулей и API 1:1.
- ERB → ECR (единственная видимая замена, язык-то другой).
- Команды: `crails` вместо `rails` (`crails new`, `crails server`,
  `crails generate`, `crails console`, `crails routes`, `crails db:migrate`).

## Зачем

Эксперимент для замера **монолитной архитектуры Rails MVC на Crystal**:

- сколько пользователей (RPS, одновременных соединений) выдержит монолит;
- сколько джобов в секунду выполнит (ActiveJob-совместимый воркер);
- сколько вебсокетов сможет держать (ActionCable-совместимый сервер);
- сколько при этом съест памяти, как быстро стартует.

Возможно это «новый король стартапов», а возможно «полный провал» —
узнаем цифрами, не эмоциями. Бенчмарки: `bench/`.

Исследование переносимости API (по реальному коду Rails 8.2): ~85–90%
ежедневного API переносится с ощущением 1:1 — полный отчёт:
`/home/oleg/egui.cr/plans/crails-api-research.md`.

## Структура (монорепо шардов)

| Папка | Порт | Статус |
|---|---|---|
| `active_support.cr/` | ActiveSupport | Iteration 0 slice + Inflector |
| `active_record.cr/` | ActiveRecord | read-срез (datalake 1:1, 29 спеков) |
| `action_pack.cr/` | ActionPack (контроллеры, роутинг, params) | Iteration 0 slice (роутер, Base, render+layout) |
| `action_view.cr/` | ActionView (хэлперы, ECR, форм-билдер) | Iteration 0 slice (h/html_escape) |
| `action_mailer.cr/` | ActionMailer | план |
| `action_mailbox.cr/` | ActionMailbox | план |
| `action_text.cr/` | ActionText | план |
| `action_cable.cr/` | ActionCable | план |
| `active_job.cr/` | ActiveJob | план |
| `active_storage.cr/` | ActiveStorage | план |
| `railties.cr/` | Railties + CLI `crails` | Iteration 0 + console (icr.cr) |
| `devise.cr/` | Devise (порт гема) | план |
| `hello_world/` | первая итерация — Hello World на CRails | ✅ работает |
| `bench/` | сценарии замеров монолита | 000-hello снят |
| `assets/` | иконка: сине-голубой алмаз Crystal | есть |

Имена шардов в `shard.yml` — без `.cr` (`active_record`, `action_pack`, …);
`.cr` в именах папок — чтобы не конфликтовать с исходниками.

## Сборка и запуск

```sh
rake            # build всего: deps шардов, crails CLI, бинарь приложения
./bin/server    # сервер демо-приложения (-p PORT, -e ENV)
./bin/console   # rails-console (config/database.yml, DATABASE_URL перекрывает)
rake spec       # все тест-сьюты шардов
```

## Дорожная карта

**Iteration 0 (Hello World) — ✅ сделана** (2026-10-02): `crails new` →
`crails server` → `curl /` → 200; CLI `new/server/routes/watch`; цифры в
`bench/results/000-hello.md` (hello RPS ~142k против Rails 8.1+Puma ~233,
RSS 16 MB против 110 MB). Приложение: `hello_world/hello/` (сгенерировано
`crails new`, пересоздаётся с нуля за ~2 s компиляции).

Дальше — `PLAN.md` в корне: Iteration 1 (active_support полный P0), затем
active_record.cr и остальные шарды.

## License

MIT (когда будет что лицензировать).
