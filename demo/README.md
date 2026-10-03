# CRails Notes — демо на полном стеке

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Мини-блог + аккаунты + чат-бот: светлая серо-голубая тема, цветные
карточки, счётчик просмотров, flash-баннеры, валидации с экраном
ошибок. Показывает весь стек порта:

| Слой | Что задействовано |
|---|---|
| railties.cr | `crails server` (сборка + boot), env-конфиги |
| action_pack.cr | роуты, контроллеры, implicit render, `redirect_to` + flash, сессии (cookie store), `rescue_from` → 404, cookies |
| action_view.cr | ERB: layout + yield, partial collection, `form_tag`/`text_area_tag`/`button_to`, `data-confirm`-атрибуты, `content_for` (page_js) |
| active_record.cr | PostgreSQL: CRUD, order/limit, валидации, `errors.full_messages` |
| devise.cr | пароли: bcrypt + pepper, validatable-валидации, `update_with_password` в профиле |
| action_cable.cr | WS-эндпоинт `/cable` (монтируется в `Application#call`), канал с `perform_action`-диспетчеризацией |

## Запуск

```sh
psql -U root -h /var/run/postgresql -d crails_demo -f db/seeds.sql  # 6 заметок
./bin/crails server        # http://127.0.0.1:3200
```

## Флоу

- `/notes` — сетка карточек; `/notes/:id` — статья (+1 просрос за показ);
- `/notes/new` — форма; пустой заголовок → 422 + ошибки валидации;
- удаление — кнопка с иконкой и Rails-стилем `data-confirm` (JS в layout);
- `/signup` · `/login` · `/logout` — аккаунты (сессия в cookie `crails_session`);
- `/profile` — редактирование имени/email/пароля через devise
  `update_with_password` (нужен текущий пароль);
- `/chat` — чат-бот: напишите число, бот ответит его квадратом через
  WebSocket (`ChatChannel#square`, регистрация не нужна).

## Проверено

- страницы 200, профиль гостя → 302 на логин;
- signup → 302 + session/flash-куки; короткий пароль → 422 + ошибки;
  неверный пароль → 422; logout → 302;
- WS-клиент (script ниже) получает welcome и `12² = 144`:

```sh
crystal run /tmp/chat_check.cr   # ws://127.0.0.1:3200/cable
```

## Известные упрощения

- удаление через POST-роут (нет `_method`-override для DELETE);
- «render :new» при ошибке — через хелпер `render_action` (implicit render
  знает только текущий экшен);
- `CableValue` — рекурсивный алиас: ответы бота уходят через `JSON.parse`;
- data-confirm — Hash-форма (`data: {"confirm" => "..."}`), NamedTuple-
  литерал в `**opts` не кастится в `Hash(String, String)`.
