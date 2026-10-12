# 205-typed-params — валидация type-safe params (Iteration 10)

Микробенч `ActionController::TypedParams` против настоящего dry-schema
1.13.4 (`Dry::Schema.Params` — оракул итерации) и против strong params
(`require`+`permit`, actionpack 8.1.4) на обеих сторонах. Схема — как в
оракуле: 5 полей (string с min/max size, Int32 с gteq/lteq, вложенный
hash, array-of-string с min_size, maybe-bool), 2-секундный цикл в одном
потоке, корректность проверяется внутри скриптов (невалидный кейс
обязан дать 5 ошибок, коарсинг "7"→7).

- Скрипты: `action_pack.cr/bench/typed_params_bench.{cr,rb}` +
  `action_pack.cr/bench/typed_permit_bench.rb` (dry-schema и actionpack
  нельзя в одном процессе — dry-core пинит старый activesupport).
- Машина: та же, что остальные замеры (bench/PLAN.md). Ruby 3.4.5,
  Crystal 1.21 (--release). 3 прогона, медиана.

| Сторона | валидный call (ops/s, 3 прогона) | медиана |
|---|---|---|
| TypedParams (Crystal, --release) | 886846 / 975288 / 848592 | **886846** |
| dry-schema 1.13.4 (Ruby) | 32368 / 29798 / 16616 | **29798** |

| Сторона | невалидный (ошибки) | медиана |
|---|---|---|
| TypedParams (Crystal) | 677253 / 695928 / 671117 | **677253** |
| dry-schema 1.13.4 (Ruby) | 24501 / 22673 / 11156 | **22673** |

| Сторона | strong permit (baseline) | медиана |
|---|---|---|
| Parameters.permit (Crystal) | 1537587 / 1440660 / 1586742 | **1537587** |
| actionpack 8.1.4 permit (Ruby) | 67456 / 80555 / 76730 | **76730** |

**~30× vs dry-schema** на идентичной семантике (verdict/коарсинг/
ошибки — оракул 42 кейса), и ~11.6× против Rails-permit на Ruby.
Внутри Crystal типизированная валидация стоит ~0.58× от нетипизирован-
ного permit (887k vs 1538k ops/s) — цена коарсинга, дерева ошибок и
boxed-вывода; при этом TypedParams заменяет и permit, и ручные
`to_i`/проверки в контроллере, а доступ к полям остаётся
compile-checked: `from` + типизированный геттер — 900k ops/s.

Пути: валид 887k = 1.13 µs/запрос, невалид 677k = 1.48 µs — на фоне
~12 µs/запрос полного hello-RPS стека (bench 000/501) цена
типизированных параметров в шуме.

Сборка OpenAPI-документа (замер `bench/openapi_bench.cr`: 3 resources +
2 кастомных роута, 2 типизированные схемы, документ 4.9 KB):
21.3k docs/s ≈ 47 µs — только на GET /openapi.json, запрос-путь
приложения не затрагивает.
