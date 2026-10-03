# rails_hello — интеграционное приложение на полном стеке CRails

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

1:1-зеркало Ruby-референса `../bench/rails_hello` (Rails 8.1): те же
маршруты, контроллеры, ERB-вьюхи и модель. Один HTTP-харнесс
`oracle/http_cases.rb` гоняется против обоих приложений — обе версии
проходят одну и ту же фикстуру `oracle/expected.yml` (правило AGENTS.md),
сейчас **9/9**.

Стек: railties (crails server) + action_pack (роуты/контроллеры/render,
rescue_from → 404) + action_view (ERB: layout/partial collection/
form_tag/text_field_tag/submit_tag, HTML-экранирование) + active_record
(PG, order/limit/find/create, валидации).

## Запуск

```sh
make seed-crails   # TRUNCATE + 3 фиксированных поста в crails_hello_test
./bin/crails server           # сборка + http://127.0.0.1:3101
```

## Оракул

```sh
make oracle-record            # поднять Rails-референс :3100, переснять expected.yml
make oracle-check             # сиды + CRails :3101 + check против expected.yml
```

Кейсы: root HTML, /posts (partial collection + form_tag, экранирование
`& <`), /posts/:id JSON (в т.ч. спецсимволы), 404 (RecordNotFound +
несуществующий маршрут), POST /posts (create) + чтение созданного.
Нормализации: строка «Served by …» и bench-таймстемпы; тела и content-type
404-страниц — плейсхолдеры (framework error pages).

## Отклонения от Rails-референса

- `render(json: …)` — именованный аргумент (позиционный `render(String)`
  в action_pack зарезервирован за partial);
- models наследуют `ActiveRecord::Base` напрямую (нет ApplicationRecord —
  AR-кодеген мапит класс на таблицу);
- приветствие — «Served by CRails x (Crystal).» вместо Rails-строки
  (нормализуется харнессом).
