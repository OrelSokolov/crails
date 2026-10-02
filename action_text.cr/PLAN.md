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

## Фазы

- P0: `has_rich_text` + RichText-модель + to_s/to_plain_text.
- P1: аттачменты (sgid + ActiveStorage), кастомный партиал.
- P2: to_markdown, галереи, encrypted.

## Готово, когда

модель с `has_rich_text :body` сохраняет и рендерит rich text с
встроенной картинкой-аттачментом.

## Зависимости

active_record.cr, active_storage.cr, active_support.cr, lexbor.
