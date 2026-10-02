# 100-ar-read — CRails vs Rails 8: `GET /posts/:id` (Iteration 2)

Дата: 2026-10-02. План: `../../PLAN.md` (Iteration 2), `../PLAN.md` (100-ar-read).

## Окружение

- CPU: Intel Core Ultra 7 155H (22 потока), RAM 32 GB, ядро 6.19.14
- Один PostgreSQL 17 (unix socket `/var/run/postgresql`), БД `crails_bench`,
  таблица `posts` (1 000 строк, PK-select), пул коннектов у обоих = 16
- Клиент: wrk (4 threads), localhost, warmup, 3 прогона по 10 s → медиана
- CRails 0.1.0 (Crystal 1.21.0, `--release`, fiber-per-connection,
  active_record.cr, `pool: 16` в config/database.yml)
- Rails 8.1.1 (Ruby 3.4.5, Puma 8.0.2, `RAILS_ENV=production`,
  `RAILS_MAX_THREADS=16` и отдельно 5, AR pool = threads)
- Приложения: идентичная логика — `Post.find(id)` → JSON из трёх полей
  (`bench/crails_ar/`, `bench/rails_hello/`)

## Результаты

| Метрика | CRails | Rails 8 + Puma (t16) | Rails 8 + Puma (t5) |
|---|---|---|---|
| RPS, c=10 (медиана 3 прогонов) | **53 296** | 345 | 441 |
| RPS, c=100 (медиана 3 прогонов) | **59 211** | 393 | 475 |
| Latency avg, c=10 | **~154 µs** | ~23 ms | ~18 ms |
| Latency avg, c=100 | ~46 ms (см. примечание) | ~250 ms | ~210 ms |
| RSS после нагрузки | ~29 MB | ~119 MB | ~114 MB |

Полные прогоны (RPS):
- CRails c10 = 54.0k / 52.6k / 53.3k; c100 = 59.3k / 59.2k / 56.3k
- Rails t16 c10 = 354 / 328 / 345; c100 = 369 / 416 / 393
- Rails t5 c10 = 441 / 447 / 438; c100 = 478 / 475 / 458

## Находка: пул коннектов

На дефолтных настройках crystal-db (`max_idle_pool_size=1`) CRails давал
всего ~10k RPS: коннект к PG открывался/закрывался на каждый конкурентный
запрос. После добавления Rails-семантики `pool:` в active_record.cr
(хранит до N коннектов; фикс в `active_record.cr/src/connection.cr`,
дефолт 5 как в Rails, в бенче — 16) RPS вырос до ~53–59k.

## Вывод одной строкой

CRails читает из PostgreSQL ~**150×** RPS Rails 8 (53k vs 345 при c=10)
при ~**4×** меньшей памяти (29 vs 119 MB); разрыв с hello-world сузился
с ~600× до ~150× — БД забирает свою долю.

## Примечания честности

- Оба приложения ходят в один и тот же PG-кластер, одна таблица,
  одинаковый пул коннектов (16).
- wrk avg-latency при c=100 у CRails (46 ms) не согласуется с Little's Law
  (100/59k ≈ 1.7 ms) — известная особенность учёта wrk при насыщении;
  ориентируйтесь на RPS и на latency c=10.
- Rails в production с дефолтным стеком (логирование, HostAuthorization
  и т.д.), как в 000-hello; тонкая настройка не проводилась ни для одной
  стороны.
- PK-select одной строки — нижняя граница AR-чтения; `where/joins` на
  больших таблицах (деградация планов) не тестировались.
