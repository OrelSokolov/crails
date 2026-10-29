# CRails Notes — демо на полном стеке

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Мини-блог + аккаунты + чат-бот: светлая серо-голубая тема, цветные
карточки, счётчик просмотров, flash-баннеры, валидации с экраном
ошибок. Показывает весь стек порта:

| Слой | Что задействовано |
|---|---|
| railties.cr | `crails server` (сборка + boot), env-конфиги, static-middleware (propshaft-резолвинг `/assets/*`) |
| action_pack.cr | RESTful-роуты (`resources :notes`), контроллеры, `rescue_from` → 404, сессии (cookie store), strong parameters (`params.require.permit`), `_method`-override (PATCH/DELETE через POST-формы) |
| action_view.cr | ERB: layout + yield, partial collection, `form_with` + FormBuilder, `button_to` (метод через `_method`), path-хелперы (`notes_path`/`note_path`), `content_for` (page_js) |
| active_record.cr | PostgreSQL: CRUD, order/limit, валидации, `errors.full_messages`, `attribute … default:` |
| devise.cr | пароли: bcrypt + pepper, validatable-валидации; HTTP-слой: `devise_for :users` (сессии `/users/sign_in` · `DELETE /users/sign_out`), хелперы `current_user`/`authenticate_user!`, `update_with_password` в профиле |
| action_cable.cr | WS-эндпоинт `/cable` (монтируется в `Application#call`), канал с `perform_action`-диспетчеризацией |
| turbo.cr | `turbo_stream_from`, broadcasts (`inserts_by: :prepend`), `destroy.turbo_stream.erb` |

## Запуск

```sh
psql -U root -h /var/run/postgresql -d crails_demo -f db/seeds.sql  # 6 заметок
./bin/crails server        # http://127.0.0.1:3200
```

## Флоу

- `/notes` — сетка карточек; `/notes/:id` — статья (+1 просмотр за показ);
- `/notes/new` — форма (`form_with model:`); пустой заголовок → 422 + ошибки валидации;
- удаление — `button_to … method: "delete"` с Rails-стилем `data-confirm`
  (JS в layout), на сервер уходит `DELETE /notes/:id` через `_method`-override;
- `/users/sign_in` · `DELETE /users/sign_out` — devise-сессии
  (warden-ключ в cookie `crails_session`);
- `/signup` · `/profile` — аккаунты: регистрация, смена email/пароля через
  devise `update_with_password` (нужен текущий пароль, `PATCH /profile`);
- `/chat` — чат-бот: напишите число, бот ответит его квадратом через
  WebSocket (`ChatChannel#square`, регистрация не нужна).

## Проверено

- страницы 200; профиль гостя → 302 на `/users/sign_in`;
- signup → 302 + сессионная кука; короткий пароль → 422 + ошибки;
  неверный пароль → 422; logout (DELETE) → 303;
- создание заметки → 302 на `/notes/:id`; удаление по `DELETE` → 302,
  turbo-stream вариант отдает `<turbo-stream action="remove">`;
- WS-клиент получает welcome и `12² = 144`:

```sh
crystal run /tmp/chat_ws_smoke.cr   # ws://127.0.0.1:3200/cable
```

## Известные упрощения

- «render :new» при ошибке — через хелпер `render_action` (implicit render
  знает только текущий экшен);
- `data-confirm` — Hash-форма (`data: {"confirm" => "..."}`), NamedTuple-
  литерал в `**opts` не кастится в `Hash(String, String)`;
- у framework-контроллеров devise `current_user : ActiveRecord::Base+?`,
  поэтому layout сужает его до `User` через `as?(User)`.
