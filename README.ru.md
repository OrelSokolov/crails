# CRails — Clean Rails - The most beautiful compiled web framework

<p align="center">
  <img src="assets/icon.svg" width="200" alt="CRails — Clean Rails" />
</p>

> ⚠️ **EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.**
> Это эксперимент. Мы замеряем производительность и смотрим, что
> получится на данный момент. Никаких гарантий совместимости.

## Текущий статус: порт Ruby on Rails

На данный момент CRails — это просто **порт Ruby on Rails на Crystal**.
Мы стараемся перенести фреймворк в текущем виде: сам фреймворк,
его дух и красоту кода. Код портируется с Rails один к один, чтобы
позже можно было сделать рефакторинг. Это черновик (draft) — даже ещё
не первый релиз.

## Философия

Философия проекта — явные контракты прежде всего, уроки Rails и Ruby,
почему Crystal, а не Rust, и обещания, которые фреймворк собирается
держать, — живёт в **[IDEA.md](IDEA.md)**. Это фактически дорожная
карта и обещание на будущее, а не описание того, что уже реализовано.

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

### Производительность: базовая Hello-страница (без БД), head-to-head

Два минимальных приложения — роут `/` → контроллер → `render plain: "Hello"`,
никакой базы, шаблонов и ORM. Оба в production-режиме, одна машина,
`wrk -t4 -c100 -d15s` после warm-up. CRails — `crystal build --release`
(нативный бинарь 5.4 MB, полный стек middleware: request-id, secure headers,
логирование). Rails 8.1.4 — дефолтный Puma 8.0.2 (1 процесс × 3 потока),
Ruby 3.4.5. Воспроизведение: `~/crails_compare/bench.sh`, полный отчёт:
`~/crails_compare/RESULTS.md`.

| Метрика | CRails 0.1.0 (Crystal 1.21) | Rails 8.1.4 (Ruby 3.4.5) |
|---|---|---|
| **RPS** | **~50 000–52 000** | **~390–470** |
| Latency (avg) | ~2 ms | 211–256 ms |
| RSS idle | 11 MB | 99–100 MB |
| RSS под нагрузкой (peak) | 17 MB | 101–102 MB |
| Socket errors / non-2xx | 0 | 0 |

Разгон больше чем **в 100 раз по RPS** при **в 6–9 раз меньшей памяти**
(два независимых прогона, воспроизводимо). Rails упирается в 3 потока
Puma по умолчанию: latency 200+ ms — это очередь на соединениях. Больше
воркеров/потоков поднимут RPS, но ценой кратного роста RAM (~100 MB
на процесс и так против 11–17 MB на всё приложение у CRails).

## License

MIT 
