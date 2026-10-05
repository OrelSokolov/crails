# 401-turbo-streams — Turbo Streams broadcast pipeline (Iteration 19)

Окружение: Intel Core Ultra 7 155H (22 ядра), 32 GB RAM, Linux 6.19.14.
CRails: Crystal 1.21.0, `turbo_cr` 2.0.20-cr (ActionHelper.action_tag +
ActionCable Async-pubsub fanout). Standalone-бинарь без HTTP:
`bench/crails_turbo` (`./bench.sh [subs] [msgs]`, 3 прогона).

Что меряем — ядро пути Turbo Streams из turbo-rails:
`broadcast_action_to(stream, :prepend, target:, content:)` —
построение `<turbo-stream>`-тега (SafeString) + broadcast в
cable-сервер + доставка всем подписчикам стрима. Отдельно — изолированный
рендер тега без доставки. Замер in-process (колбэки-подписчики, без WS):
нижняя граница стоимости сервера на броадкаст.

## Данные (subs=10, msgs=10 000, payload 116 B; медианы из 3 прогонов)

| метрика | значение |
|---------|----------|
| изолированный рендер turbo-stream тега | **2.1–2.7M renders/s** |
| broadcasts/s (рендер + enqueue, Async-адаптер) | **1.3–1.8M/s** |
| deliveries/s (10 подписчиков) | **12.7–18.5M/s** |
| полный цикл 10k броадкастов × 10 подписчиков | **5.4–7.9 ms** |

Пример прогона (медианный):

```json
{"subs":10,"msgs":10000,"renders_per_s":2297028.03,
 "broadcasts_per_s":1546564.11,"delivered":100000,
 "deliveries_per_s":15465413.84,"fanout_wall_ms":6.47,"payload_b":116}
```

## Контекст

- Референс pubsub-адаптеров без рендера — `results/202-pubsub.md`:
  доставка через PG LISTEN/NOTIFY и Redis там же порядка 50–100k msg/s
  (cross-process); здесь Async-адаптер in-process, поэтому цифры на
  порядок выше — это цена turbo-слоя (тег + SafeString + dispatch), а не
  транспорта.
- E2E-путь целиком (HTTP POST → AR create → after_commit → async-job →
  рендер партиала → pubsub → WS-клиент) проверен смоуком
  `turbo.cr/spec/e2e_smoke.cr` против demo-приложения; latency-бенч
  полного HTTP-цикла оставлен на следующую итерацию (нужен wrk-сетап с
  формами, как в `101-ar-crud`).
- Rails-аналог для честного парного сравнения (turbo-rails + Sidekiq +
  Redis-адаптер) не поднимался: модель доставки принципиально другая
  (отдельный процесс-воркер), сравнивать in-process enqueue с
  cross-process брокером некорректно. Зафиксировано как честное
  ограничение, а не как победа.

## Выводы

- Тег turbo-stream строится за ~0.4–0.5 µs — рендер никогда не будет
  узким местом Turbo Streams на этом стеке; цена реального броадкаста
  доминируется AR-запросом и сериализацией партиала (путь demo: create +
  after_commit + async-job ≈ единицы ms end-to-end по логам сервера).
- Fanout подписчикам почти линейный (deliveries/s ≈ broadcasts/s × subs,
  копеечный колбэк): узким местом при росте аудитории станет транспорт
  (WS-запись, cork-буферы action_cable P1.5), не turbo-слой.

## Критерий готовности (Iteration 19)

- [x] Оракул 60 кейсов turbo-rails 2.0.20 зелёный (`turbo.cr`,
      `make spec`)
- [x] Регресс соседей: active_support 269, action_view 109, action_pack
      53, action_cable 25, active_job 56 — 0 failures
- [x] E2E smoke demo: подписка /cable → create (prepend), show (replace),
      destroy (HTTP turbo_stream + remove) — PASSED
- [x] Бенч зафиксирован (этот файл)
