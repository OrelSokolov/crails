# 400-liveview — event/diff round-trip против настоящего Phoenix (Iteration 8)

Окружение: Intel Core Ultra 7 155H (22 ядра), 32 GB RAM, Linux 6.19.14.
CRails: Crystal 1.21.0, `live_view_cr` (fiber-per-connection, ручной
ws-upgrade c TCP_NODELAY, статика/dynamics-диффы). Референс: настоящий
Phoenix LiveView 1.2.12 (hex, phoenix 1.8.15) + Bandit 1.12.5,
Erlang/OTP 27, Elixir 1.18.3 — тот же бинарь, с которого снят wire-оракул
(`live_view.cr/oracle/app`). Клиент: `bench/loadgen/lv_load.cr` —
Crystal fiber-клиенты, Phoenix Channels V2 (join → closed-loop
`event "incr"` → phx_reply c диффом), TCP_NODELAY на клиенте.

Вьюха-зеркало: `BenchCounterLive` на обеих сторонах (один DOM, один
event-loop). Серверы: `bench/crails_lv/server.cr` (порт 4400) и
`live_view.cr/oracle/app` (`mix run --no-halt`, порт 4177, токен через
`/mint`).

## Данные

### CRails (live_view_cr)
| clients | events | ev/s (2 прогона) | p50 | p99 |
|---------|--------|------------------|-----|-----|
| 4  | 80 000  | **58 950**            | 52 µs  | 471 µs  |
| 16 | 320 000 | **61 296** / 51 951   | 216–254 µs | 1.0–1.2 ms |

### Phoenix LiveView (Bandit)
| clients | events | ev/s (2 прогона) | p50 | p99 |
|---------|--------|------------------|-----|-----|
| 4  | 80 000  | **39 435**      | 85 µs  | 344 µs |
| 16 | 320 000 | **87 845** / 67 763 | 170–194 µs | 0.65–0.96 ms |

### Память (после нагрузки)
| сервер | VmRSS |
|--------|-------|
| CRails live_view_cr | **14 MB** |
| Phoenix LiveView (BEAM) | 129 MB |

## Выводы

- **CRails ~52–61k ev/s против Phoenix 39–88k** — на 4 клиентах наш
  P0 быстрее (58k vs 39k), на 16 Phoenix выигрывает за счёт BEAM-шедулеров;
  разброс прогонов ±20%. Итог: один порядок, ~0.7–1.5× от Phoenix.
- **RSS: 14 MB против 129 MB — в 9 раз меньше** (fiber против BEAM-процесса
  на канал).
- **Главная причина отставания на 16 клиентах — однопоточный рантайм**:
  Crystal исполняет все файберы на одном потоке ОС (одно ядро из 22;
  MT в Crystal — preview). BEAM держит планировщик на каждое ядро, так
  что Phoenix параллелит рендер/диффы по всем ядрам. Отсюда профиль:
  на 4 клиентах (латентность доминирует) CRails быстрее — 58k vs 39k,
  на 16 (нужны вычисления) Phoenix уходит вперёд. Удельная скорость на
  ядро у CRails выше (~61k на одном ядре vs 88k на двадцати двух).
  Вертикальный ответ — N воркеров за LB (Iteration 15, `crails supervise`).
- Локальные шаги оптимизации P0: cork/encode-once по образцу action_cable
  P1.5 (меньше CPU на событие), finer-grained change-tracking.
- Методологическая ловушка, задокументированная здесь: без TCP_NODELAY
  обе стороны дают ровно 97 ev/s при p50 = 41 ms — это Nagle+delayed-ACK
  стенка закрытого цикла мелких фреймов, а не сервер. Loadgen и
  `live_view_cr` upgrade ставят NODELAY явно.

## Критерий готовности (Iteration 8)

Немодифицированный официальный клиент `phoenix_live_view` 1.2.12 (npm,
vendored) подключается к demo `/live`: join → mount → клик → дифф →
DOM-патч — подтверждено headless Chromium (`E2E_OK`, см. PLAN.md шарда).
