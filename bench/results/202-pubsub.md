# 202-pubsub: кросс-процессный pubsub — PG LISTEN/NOTIFY vs Redis

Конфигурация: `bench/crails_pubsub` (ноутбук, Crystal 1.21.0 release,
PG/redis локально). Один процесс, 10 подписчиков на канале, 10 000
broadcast'ов, payload 42 байта (типичный cable-конверт). Медиана из 3.

| адаптер | broadcast/s | доставок/s (10 подписчиков) | wall ms |
|---------|------------:|----------------------------:|--------:|
| PG (LISTEN/NOTIFY)  |  35 107 | 339 145 | 295 |
| Redis (PUBLISH)     | 108 888 | 981 862 | 102 |

Контекст: in-process Async-адаптер (P1.5 fast broadcast) — 2.72M msg/s
(`results/310-ws-bun-matrix.md`); Rails ActionCable Redis-адаптер на
этом железе давал ~6.7k msg/s end-to-end (`results/300-websockets.md`).

Выводы:
- Оба сетевых адаптера снимают потолок «одного процесса» на 2–3 порядка
  ниже in-process; Redis pubsub — ~3× PG NOTIFY по broadcast/s.
- PG NOTIFY достаточно для монолита (35k broadcast/s на стрим), Redis —
  штатная опция для высокочастотных стримов.
- Ограничение PG: payload NOTIFY ≤ ~8000 байт (задокументировано в
  адаптере); у Redis лимита на практике нет.
