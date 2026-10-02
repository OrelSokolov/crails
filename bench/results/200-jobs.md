# 200-jobs — queue throughput (Iteration 4)

Окружение: Intel Core Ultra 7 155H (22 ядра), 32 GB RAM, Linux 6.19.14.
CRails: Crystal 1.21.0, `active_job_cr` AsyncAdapter (in-process fiber
pool + Channel). Референсы: Rails 8.1.4 (Puma 8.0.2, Ruby 3.4.5)
— :async адаптер (Concurrent thread pool) и Sidekiq 7.3.9 + Redis
(db3, isolated). Джоба no-op: измеряется чистый оверхед очереди
(enqueue → perform). 3 прогона на точку, медиана.

## Данные

### CRails async (fiber pool), pool=16
| jobs   | jobs/sec | avg ms | p99 ms | max ms | RSS KB |
|--------|----------|--------|--------|--------|--------|
| 10000  | 434782   | 6.02   | 9      | 9      | 11964  |
| 50000  | 862068   | 20.7   | 39     | 39     | 16452  |
| 100000 | 1030927  | 40.03  | 77     | 78     | 16488  |

pool=64 — в пределах шума (0.33–1.1M jobs/s, RSS ≤ 18 MB): fiber-пул
не узкое место.

### Rails :async (Puma, 50 threads, ActiveJob async)
| jobs   | jobs/sec | avg ms | p99 ms | max ms | RSS KB |
|--------|----------|--------|--------|--------|--------|
| 10000  | 31055    | 189.12 | 281    | 292    | 110920 |
| 50000  | 32299    | 828.2  | 1502   | 1518   | 163660 |
| 100000 | 33003    | 1525.08| 2859   | 2883   | 258592 |

### Rails + Sidekiq 7.3.9 + Redis (1 воркер, default concurrency)
| jobs   | jobs/sec | avg ms  | p99 ms | max ms | RSS KB (web+sidekiq) |
|--------|----------|---------|--------|--------|----------------------|
| 10000  | 1506     | 3322    | 6543   | 6616   | ~85860+?             |
| 50000  | 1332     | 18467   | 37080  | 37484  | ~94192+?            |
| 100000 | 1382     | 33816   | 71411  | 72264  | ~113080+?           |

Sidekiq-латентности — это очередь при насыщении (100k джобов уходит в
Redis одним пакетом, воркер разгребает минуты). RSS в таблице —
puma-процесс (sidekiq-воркер ~81 MB отдельно). Durability (kill -9)
не мерилась — вне скоупа этого прогона; отмечено как TODO.

## Вывод

CRails async держит ~1M jobs/sec (медиана 100k) при RSS 16 MB —
~31× Rails :async (~32k jobs/sec, RSS 259 MB) и ~700× Sidekiq+Redis
(~1.4k jobs/sec на 1 воркере) на no-op нагрузке. Латентность
enqueue→perform: 40 ms vs 1.5 s vs 34 s на 100k.

Конфигурации: `crails_jobs/bench.sh`, `rails_jobs/bench.sh`.
