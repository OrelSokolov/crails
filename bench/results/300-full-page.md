# 300-full-page — CRails vs Rails 8: `GET /posts` (Iteration 3)

Дата: 2026-10-02. План: `../../PLAN.md` (Iteration 3), `../PLAN.md`.

## Сценарий

Полная HTML-страница через весь MVC-контур: PostgreSQL-запрос (20 строк,
`ORDER BY id LIMIT 20`) → ERB-шаблон с layout → collection-partial
(20 рендеров) → `form_tag` с `text_field`/`submit`. Это первый бенч
Iteration 3: action_view (ERB-компилятор, партиалы, формы) + action_pack
(роутинг, контроллеры, params) + active_record.

- CRails: `bench/crails_ar` (порт 3101), `.html.erb`-шаблоны, скомпилиро-
  ваны в бинарник на этапе сборки (`--release`), binary 5.8 MB.
- Rails: `bench/rails_hello` (порт 3102), Rails 8.1.1, Ruby 3.4.5,
  Puma 8.0.2 single mode, t50, `RAILS_ENV=production`.
- Страницы байт-в-байт идентичны, кроме одного скрытого input (см.
  «Примечания честности»): 2511 vs 2440 байта.
- Тот же PG 17 (unix socket), БД `crails_bench`, 1000 сидов, пул 16.
- wrk (4 threads), warmup, 3 прогона по 10 s → медиана.

## Результаты

| Метрика | CRails | Rails 8 + Puma (t50) |
|---|---|---|
| RPS, c=10 (медиана) | **18 594** | 288 |
| RPS, c=100 (медиана) | **20 543** | 305 |
| Latency avg, c=10 | **~460 µs** (max ~1 ms) | ~28 ms (max ~90 ms) |
| Latency avg, c=100 | ~48 ms (max 231 ms)* | ~320 ms (max 833 ms) |
| RSS после нагрузки | **~25 MB** | ~132 MB |
| Время старта (до первого 200) | **~15 ms** | ~950 ms (см. 000-hello) |
| Размер артефакта | 5.8 MB (бинарник) | интерпретируемый |

Полные прогоны (RPS):
- CRails c10 = 18 555 / 18 594 / 19 650; c100 = 20 209 / 20 543 / 20 670
- Rails c10 = 288 / 287 / 290; c100 = 305 / 304 / 305

\* wrk на высоких RPS завышает перцентили (coordinated omission); RPS —
первичная метрика, латентность — для порядка величины.

## Вывод одной строкой

Полная страница (БД → layout → 20 партиалов → форма) отдаётся CRails в
**~65×** быстрее Rails 8 (18.6k vs 288 RPS при c=10; 20.5k vs 305 при
c=100) при ~5× меньшей памяти; цена — компиляция шаблонов на этапе сборки.

## Примечания честности

- Разница в 71 байт: CRails `form_tag` (оракул-копия actionview 8.1.4)
  вставляет utf8-enclave `<input type="hidden" name="utf8" ...>`; Rails
  при `authenticity_token: false` опускает и его. Разметка, данные и
  порядок строк идентичны (проверено `diff`, отличие — одна строка).
- Обе стороны без CSRF-токена в форме (CRails слоя CSRF не имеет;
  Rails — `authenticity_token: false`), см. также 101-ar-crud.
- Rails-сторона запущена с дефолтным `bin/rails server` (Puma single
  mode, t50 — конфиг приложения; в 000/100 использовался t16: на
  результат влияет слабо, Rails упирается в CPU на рендере).
- Newline-семантика шаблонов выровнена по Rails 8.1 (`load_defaults`):
  action-шаблоны — chomp одного завершающего `\n`, партиалы и layout —
  байт-в-байт; зафиксировано оракул-тестами action_view.cr.
- SELECT — один на запрос (нет N+1), кеша шаблонов нет ни у одной
  стороны: CRails — компиляция в код, Rails — production-кеш Erubi.
