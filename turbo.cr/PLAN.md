# turbo.cr — порт turbo-rails (Turbo Streams)

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `Turbo`. Порт гема **turbo-rails 2.0.20** (Hotwire Turbo
Streams) поверх action_view/action_pack/action_cable/active_job.
Клиентская часть — официальный `@hotwired/turbo` 8.0.13 UMD
(vendored в `demo/public/turbo.js`) + миниатюрный cable-connector
вместо npm-сборки turbo-rails (см. «Отклонения»).

## Что реализовано (Iteration 19, P0)

- **StreamsTagBuilder** (`turbo_stream`): 7 действий
  append/prepend/before/after/replace/update/remove (+ `refresh`,
  кастомный `action`/`action_all`), пары оверлоадов с блоком/без.
  Семантика вывода зафиксирована оракулом: позиционный content — без
  экранирования, блок — экранируется, `html:` — экранируется,
  `method:`/доп. атрибуты — перед action/target.
- **Turbo::StreamsChannel** + Broadcasts: `broadcast_*_to` для всех
  действий, `broadcast_action_to`, `broadcast_stream_to`,
  `broadcast_render_to` (turbo_stream-шаблон), подписанные имена
  стримов (`signed_stream_name`/`verified_stream_name` через
  ActiveSupport::MessageVerifier; digest — HEX).
- **Turbo::Broadcastable** (миксин AR-моделей): декларативные макросы
  `broadcasts`/`broadcasts_to` (after_commit create/update/destroy),
  instance-API `broadcast_*`, `suppressing_turbo_broadcasts`,
  GlobalID-lite (`to_gid_param`, gid → рефетч записи в джобах).
- **_later-джобы**: ActionBroadcastJob / BroadcastJob /
  BroadcastStreamJob через ActiveJob (payload-хеш: диспетчер порта
  генерит конструкторы до 4 аргументов).
- **View-хелперы**: `turbo_stream_from` (turbo-cable-stream-source,
  подписанное имя стрима), `turbo_frame_tag` (+ блочная форма,
  content_tag-экранирование), доступны всем контроллерам и вьюхам.
- **HTTP-формат turbo_stream** (в action_pack.cr): `respond_to do
  |format| format.turbo_stream end`, дефолтный рендер
  `#{action}.turbo_stream.erb` без layout с CT
  `text/vnd.turbo-stream.html; charset=utf-8`; Accept-неготиация и
  `?format=turbo_stream`; redirect_to из turbo_stream-запроса —
  http-фоллбэк с CT text/html.

## Оракул (AGENTS.md)

`oracle/cases.rb` → `oracle/expected.yml`: 60 кейсов, снятых с
настоящего turbo-rails 2.0.20 + rails 8.1.4 (БД `crails_turbo_oracle`,
TZ=UTC). Зеркало — `spec/oracle_spec.cr` (fixtures-вьюхи в
`spec/fixtures/views`), обе стороны проходят без правок тестов.
Ожидаемые raise-кейсы (`streamables can't be blank`) — намеренно.

Запуск: `make spec` (CRAILS_VIEWS=spec/fixtures/views crystal spec).

E2E-смоук demo-приложения: `spec/e2e_smoke.cr` (нужен запущенный
`demo/bin/app serve -p 3001`): подписка на Turbo::StreamsChannel по
signed-stream-name со страницы /notes → POST /notes (prepend по
cable), GET /notes/:id (replace, views+1), POST destroy с Accept
turbo-stream (HTTP-ответ remove + remove по cable).

## Отклонения от Ruby API (осознанные)

- **kwargs → named args**: `turbo_stream.append target, "text"` и
  именованные аргументы вместо `**options`.
- **Renderer seam вместо ApplicationController.render**: компилируемый
  язык не умеет рантайм-рендер по строке — приложение регистрирует
  `Turbo.partial_renderer` / `Turbo.template_renderer` (проки на
  compile-time-скомпилированные партиалы/шаблоны). Boilerplate
  приложения — в `spec/oracle_spec.cr` (TurboView) и demo
  (`src/turbo_renderers.cr`).
- **`broadcasts`-макрос**: pluralize — рантайм-инфлектор, в макро-мире
  недоступен, стрим-имя вычисляется в рантайме.
- **Клиентский JS**: вместо npm-сборки turbo-rails — vendored
  `@hotwired/turbo` UMD + ~60 строк `demo/public/turbo_cable.js`
  (WS-подписка на Turbo::StreamsChannel + renderStreamMessage).
  Поведение идентично cable.js из turbo-rails.
- **Не в P0**: `renderable:`-объекты (P2), proc-стримы и
  `broadcast_refresh_to` с атрибутами (в 2.0.20 их нет — оракул это
  фиксирует), debounce в `broadcast_refreshes_with` (P1),
  Turbo::Frames для `frame_loading`/`enforce_frame_routes` (нет
  аналога в порте роутинга).

## Crystal-кварки, учтённые в реализации

- Нетипизированный `&block`, переданный дальше как Proc, возвращает
  nil — блочные оверлоады TagBuilder/хелперов типизированы
  (`&block : Proc(String)`).
- Генерики инвариантны: `{"post" => post}` — это `Hash(String, Post)`;
  locals нормализуются через `Turbo.cast_locals`.
- ActiveJob-аргументы-хеши — строго `Hash(String | Symbol, ArgValue)`.
- `extend` внутри `macro included` не поднимает макросы: декларативные
  макросы живут в теле модуля Broadcastable, обычные методы — в
  ClassMethods-части через `macro included`.

## Дальше (P1/P2)

- [ ] P1: HTTP-фоллбэк create.turbo_stream.erb в demo, debounce
      refresh, повтор E2E в headless-браузере (сейчас — WS-клиент)
- [ ] P2: renderable, proc-стримы, frames-helpers для форм
- [ ] бенч полного HTTP-цикла (POST → turbo_stream-ответ) как в
      101-ar-crud
