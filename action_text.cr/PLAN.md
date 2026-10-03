# action_text.cr — порт ActionText

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActionText` — 1:1. Оценка: ~75% (HTML-фрагментные
трансформации + sgid-registry). Приоритет низкий.

## API 1:1

- `has_rich_text :body (encrypted: false, strict_loading:)` — макрос
  (в Rails внутри `class_eval`); генерит `body`, `body=`, `body?`,
  полиморфную ассоциацию `rich_text_body` + scope `with_rich_text_body`
- `RichText`-модель (`action_text_rich_texts`): `to_s` (HTML),
  `to_plain_text`, `to_markdown`, `to_editor_html`
- `<action-text-attachment sgid=...>` — аттачменты (ActiveStorage blobs)
  внутри контента; резолвция sgid → compile-time registry разрешённых
  классов
- Кастомный рендер-партиал: `app/views/action_text/contents/_content.html.ecr`
- `content.html` для прямого рендера
- Редактор: Trix — клиентский JS, не портируем (браузерный код работает
  как есть); контракт редактора сохраняем

## Реализация

- HTML-фрагментные трансформации (нормализация, галереи аттачментов,
  minify) — на HTML-парсере (lexbor).
- SGID-подписи через active_support.cr (MessageVerifier).

## Статус (Iteration 5 — P0 готов)

- Oracle: `oracle/cases.rb` → `oracle/expected.yml`, 48 кейсов сняты с
  actiontext 8.1.4 (SQLite in-memory, Rails::HTML4 safe-list санитайзер,
  Disk-сервис для embeds; HTML-сериализация Nokogiri HTML5, plain-text
  конверсия, links, sanitize, serialization dump/load, has_rich_text
  persistence с autosave). Зеркало: `spec/oracle_spec.cr` — 48/48.
- Реализовано: `fragment.cr` (Lexbor — сериализация 1:1 с Nokogiri
  HTML5), `plain_text_conversion.cr` (bottom-up правила 1:1: block/br/
  div/figcaption/blockquote-кавычки/ul-ol-li с индентацией, chomp("")
  семантика), `sanitizer.cr` (safe-list теги/атрибуты дословно из
  rails-html-sanitizer 1.7.1 + action-text attachment-теги; unwrap
  запрещённых с сохранением контента), `content.cr` (to_html/
  to_plain_text/links/serialize dump-load; `to_s` — статический
  trix-content layout: `<div class="trix-content">\n  …\n</div>\n`),
  `rich_text.cr` (RichText-хранилище + макрос `has_rich_text`: геттер/
  сеттер/презентс, перехват `create!/create` по rich-text-ключу,
  запись через after_create/after_update коллбэки — префикс
  `after_create__cb_` подхватывается finished-кодегеном AR).
- Отклонения от Rails (сознательные, P1+): RichText — ручной row-класс
  на `Base.connection`, не полная AR-модель (кодеген AR переопределяет
  поздние def — to_s/body недоступны для перекрытия); `RichText#body`
  — HTML-строка (как в БД), Content-объект через `to_body_content`;
  аттачменты/sgid/Trix-конверсия — P1; libxml2-\n-артефакты санитайзера
  воспроизведены только для unwrap последнего script/style-child
  (кейсы оракула покрывают); to_markdown/encrypted — P2.
- Спеки шарда: `make spec` (lexbor требует `-lm` на линковке).

## Фазы

- P0: `has_rich_text` + RichText-модель + to_s/to_plain_text.
- P1: аттачменты (sgid + ActiveStorage), кастомный партиал.
- P2: to_markdown, галереи, encrypted.

## Готово, когда

модель с `has_rich_text :body` сохраняет и рендерит rich text с
встроенной картинкой-аттачментом.

## Зависимости

active_record.cr, active_storage.cr, active_support.cr, lexbor.
