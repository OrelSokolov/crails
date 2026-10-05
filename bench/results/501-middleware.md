# 501 — Middleware stack (Iteration 12)

**Что измерялось:** цена `config.middleware`-цепочки поверх
`HTTP::Handler` (порт `ActionDispatch::MiddlewareStack`, Iteration 12)
на горячем пути HTTP-запроса:

- 4 middleware по умолчанию (RequestId, RequestLogger, ShowExceptions,
  Head) + терминальный Dispatcher вместо монолитного
  `CRails::Application#call`;
- 5 виртуальных вызовов `call_next` на запрос + инъекция Configurable;
- `X-Runtime` теперь `sprintf("%.6f")` (формат Rack::Runtime) вместо
  `.to_s`.

## Окружение

- CPU: Intel Core Ultra 7 155H (22 ядра), RAM 30 GiB, Crystal 1.21.0,
  `--release`; приложение `rails_hello` (`GET /`, рендер шаблона,
  без БД), логи → `/dev/null`
- Клиент: `/tmp/http_load.cr` — 16 fiber, keep-alive, 10 c
- A/B: старый бинарник (до Iteration 12) и новый, чередование прогонов
  на одной машине в один момент (абсолютные RPS в день замера ниже
  500-observability — состояние машины; сравнение корректно только
  внутри этого A/B)

## RPS (3 чередуемых прогона)

| Бинарик | Прогоны           | Медиана | Δ      |
|---------|-------------------|---------|--------|
| old     | 41 317 / 40 640 / 41 221 | 41 221 | — |
| mw      | 40 207 / 39 616 / 40 029 | 40 029 | −2.9% |

## Выводы

1. **Цена цепочки ~3% RPS** — постоянная стоимость 5 лишних вызовов и
   `sprintf`; в methodology-шуме 500-observability (±10%), но
   воспроизводима в чередуемом A/B. Принято: цена архитектуры, дающей
   `use/insert_before/insert_after/swap/delete` и точку вставки CSP.
2. Глубина стека не растёт от пользовательских middleware линейно по
   времени: каждая вставка — ещё один `call_next` (наносекунды), без
   аллокаций на запрос (инстансы создаются один раз при сборке цепочки).
3. HEAD-запросы: DiscardOutput подменяет `response.output` — на теле
   любой длины ничего не доходит до сокета, Content-Length
   пересчитывается как 0 (оракул head_up_content_length).
