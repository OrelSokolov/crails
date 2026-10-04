# 500 — Observability overhead (Iteration 11)

**Что измерялось:** цена observability-слоя Iteration 11 на горячем
пути HTTP-запроса в `CRails::Application#call`:

- request-id (UUID v4 генерация/passthrough + заголовки `X-Request-Id`,
  `X-Runtime`);
- Prometheus-счётчики (`METRICS.observe`: mutex + гистограмма на запрос);
- лог запроса: текстовые строки Rails-формата (Started/Processing/
  Completed) vs одна JSON-строка (`config.log_json`).

Лог во всех режимах уходил в `/dev/null` (измеряем цену форматирования
и счётчиков, не диска).

## Окружение

- CPU: Intel Core Ultra 7 155H (22 ядра), RAM 30 GiB
- Ядро: 6.19.14-061914-generic
- Crystal 1.21.0, `--release`; приложение `rails_hello` (`GET /`,
  рендер шаблона, без БД)
- Клиент: `/tmp/http_load.cr` — 16 fiber, keep-alive, 10 c, 3 прогона
  (медиана); warmup перед каждым режимом

## RPS (медиана из 3 прогонов)

| Режим                                   | RPS     | Δ к baseline | RSS под нагрузкой |
|-----------------------------------------|---------|--------------|-------------------|
| baseline (railties до Iteration 11)     | 83 671  | —            | 10.6 MB           |
| iter11, текстовый лог (Rails-формат)    | 91 028  | +8.8%        | 10.7 MB           |
| iter11, JSON-лог (`CRAILS_LOG_JSON=1`)  | 80 453  | −3.8%        | 10.6 MB           |

Прогоны (RPS): baseline 83 669 / 85 337 / 83 671; text 86 883 /
91 028 / 97 562; json 79 135 / 89 112 / 80 453. Разброс между
прогонами ±10% — text-режим «быстрее» baseline это шум машины
(общая загрузка), а не реальный выигрыш.

## Выводы

1. **Оверхед observability в пределах шума.** Текстовый режим (счётчики
   + request-id + 3 лог-строки) не медленнее baseline: медианы
   различаются меньше, чем разброс прогонов.
2. **JSON-лог: −4% RPS** (~350 c медленнее на 84k RPS) — цена
   `to_json` на запрос против трёх интерполяций строк. Приемлемо для
   production-дефолта.
3. **Память: +0–80 KB** к RSS (счётчики — константы, аллокаций на
   запрос в метриках нет).
4. OTel-экспорт в замере не участвовал: без `OTEL_EXPORTER_OTLP_ENDPOINT`
   на горячем пути один nil-check (`OTel.record_http_span` выходит
   сразу). Это by design (zero-config).

## Артефакты

- Load-генератор: `/tmp/http_load.cr` (fiber-клиент, keep-alive).
- Baseline-бинарь: railties `HEAD` до Iteration 11 (текстовый лог
  `GET / -> 200 (Nms)`), собран временной подменой
  `railties.cr/src/railties_cr.cr` на `git show HEAD`-версию.
