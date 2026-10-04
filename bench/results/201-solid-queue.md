# 201-jobs: durable queues — CRails PG (solid_queue-style) vs Redis

Конфигурация: `bench/crails_solidqueue` (ноутбук, Crystal 1.21.0 release,
PG 17 локально, redis-server локально). Джоба — no-op (чистый оверхед
очереди), 8 worker-фибер, batch 50. Медиана из 3 прогонов.
`enq`/`drain` — раздельные метрики: enqueue и drain меряются отдельно,
`jobs/s` — конец-в-конец (enqueue+drain).

## CRails PG — `ActiveJob::SolidQueue::Adapter` (durable, default)

| jobs  | enq/s | drain/s | jobs/s | avg_ms  | RSS KB |
|------:|------:|--------:|-------:|--------:|-------:|
| 1 000 |   479 |   1 525 |    364 |  2 369  | 16 780 |
| 10 000|   479 |   1 848 |    380 | 23 579  | 14 144 |

Enqueue упирается в fsync на COMMIT (каждый INSERT — отдельная
транзакция: честная цена durability, ту же цену платит solid_queue в
Rails). Drain (claim SKIP LOCKED + perform + finished) — ~1.5–1.8k/s на
8 воркерах в одном процессе. avg_ms — время жизни джобы от enqueue до
perform (растёт, пока медленный enqueue догоняет).

## CRails Redis — `ActiveJob::RedisQueueAdapter` (ephemeral)

| jobs  | enq/s  | drain/s  | jobs/s | avg_ms | RSS KB |
|------:|-------:|---------:|-------:|-------:|-------:|
| 10 000| 58 327 | 133 612  | 40 650 |    206 | 12 864 |
| 50 000| 57 572 | 149 917  | 41 631 |  1 029 | 17 332 |

## Контекст (из `results/200-jobs.md`)

| очередь                       | jobs/s        | durable |
|-------------------------------|--------------:|---------|
| CRails async (fiber-пул)      | ~1 000 000    | нет     |
| **CRails Redis (эта итерация)** | ~41 000       | нет*    |
| **CRails PG (эта итерация)**    | ~380 (drain 1.8k) | да |
| Rails async                   | ~32 000       | нет     |
| Sidekiq 8.1 (Rails, Redis)    | ~1 400        | да**    |

\* Redis-адаптер эфемерный (без finished-истории), но переживает
падение веб-процесса (джобы в Redis).
\** Sidekiq — отдельные процессы Redis + worker.

Выводы:
- Redis-очередь CRails в ~30× быстрее Sidekiq на том же Redis и в 1.3×
  быстрее Rails async при durability уровня Redis.
- PG-очередь — про надёжность монолита (одна БД, ACID, skip-locked),
  не про throughput; для фоновой нагрузки высокой интенсивности —
  Redis-адаптер или роли `worker` (Iteration 15).
- Медианы PG enqueue/drain стабильны между 1k и 10k (нет деградации).
