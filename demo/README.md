# CRails Notes — демо на полном стеке

> ⚖️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Мини-блог «заметки»: тёмная тема, цветные карточки, счётчик просмотров,
flash-баннеры, валидации с экраном ошибок. Показывает весь стек порта:

| Слой | Что задействовано |
|---|---|
| railties.cr | `crails server` (сборка + boot), env-конфиги |
| action_pack.cr | роуты (root/get/post/`:id`), контроллеры, implicit render, `redirect_to` + flash (cookies), `rescue_from` → 404 |
| action_view.cr | ERB: layout + yield, partial collection (`_note`), `form_tag`/`text_area_tag`/`button_to`, HTML-экранирование |
| active_record.cr | PostgreSQL: `order/limit/find/create/destroy/save(validate:)`, валидации presence/length, `errors.full_messages` |

## Запуск

```sh
psql -U root -h /var/run/postgresql -d crails_demo -f db/seeds.sql  # 6 заметок
./bin/crails server        # http://127.0.0.1:3200
```

## Флоу

- `/` и `/notes` — сетка карточек (цветная полоска, сниппет, дата, просмотры);
- `/notes/new` — форма: заголовок/текст/цвет-свотчи; пустой заголовок →
  422 и блок ошибок валидации;
- `POST /notes` → 302 на заметку + flash «Заметка создана» (cookie `crails_flash`);
- `/notes/:id` — статья; каждый показ делает `views = views + 1`;
- «Удалить» → `POST /notes/:id/destroy` → 302 + flash; отсутствующий id → 404.

## Известные упрощения

- удаление через POST-роут (в action_pack нет `_method`-override для DELETE);
- «render :new» при ошибке — через хелпер `render_action` (implicit render
  знает только текущий экшен);
- вложенные `<% %>`-блоки внутри `<%= form_tag do %>` не поддерживаются
  ERB-компилятором action_view (свотчи развёрнуты вручную).
