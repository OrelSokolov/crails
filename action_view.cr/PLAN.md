# action_view.cr — порт ActionView (хэлперы, ECR, форм-билдер)

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActionView` — 1:1. Оценка: ~85%. Шаблоны: **ECR вместо ERB**
(согласовано — единственная видимая замена).

## Цель

Вьюхи, пишущиеся как в Rails: те же хелперы, тот же FormBuilder,
layouts/partials/content_for.

## API 1:1

### Рендеринг (P0)
- `app/views/<controller>/<action>.html.ecr`; layouts (`layouts/application.html.ecr`,
  `yield`, `content_for :sidebar / content_for? / provide`), вложенные
  layouts
- `render partial: "shared/post", locals: {post: @post}`,
  collection-рендер (`render @posts` → `_post.ecr`,
  `post_counter`, `post_iteration.size/first?/last?`), spacer_template
- Инстанс-переменные контроллера видны во вьюхе (как в Rails)

### Форм-хелперы (P1)
- `form_with model: @post do |f| ... end` (+ `url:`, `scope:`), `fields_for`
- FormBuilder: `f.label, f.text_field, f.password_field, f.hidden_field,
  f.text_area, f.check_box, f.radio_button, f.file_field, f.select,
  f.collection_select, f.grouped_collection_select, f.submit, f.button,
  f.check_box, f.email_field, f.number_field, f.date_field, ...`,
  `f.field_id/field_name`, индексный нейминг для nested attributes
  (`post[comments_attributes][0][_destroy]`)
- Tag-варианты: `form_tag do end`, `text_field_tag, label_tag,
  select_tag, submit_tag, button_tag, hidden_field_tag, ...`

### Контент и теги (P0)
`content_tag(:div, options) { }`, `tag("br")`, `tag.br` (точечная форма —
фикс-список ~110 HTML-элементов, макрос-генерация), `raw`, `safe_join`,
`escape_once`, `capture`, `concat`; output-safety (SafeBuffer-аналог:
`html_safe`-маркер типа).

### URL/навигация (P0)
`link_to "text", path (options|block)`, `link_to_if/unless`,
`button_to`, `current_page?`, `mail_to, phone_to, sms_to`,
`url_for(model)` (полиморфизм — P2).

### Текст и числа (P0)
`pluralize, truncate, excerpt, highlight, word_wrap, simple_format,
cycle/current_cycle/reset_cycle`; `number_to_currency, number_with_delimiter,
number_with_precision, number_to_human_size, number_to_human,
number_to_percentage, number_to_phone`; `debug`,
`distance_of_time_in_words, time_ago_in_words`; `t/l` (I18n).

### Assets (P1)
`stylesheet_link_tag, javascript_include_tag, javascript_tag, image_tag,
video_tag, audio_tag, favicon_link_tag, csrf_meta_tags, csp_meta_tag`.
Sprockets/Propshaft не портируем: fingerprint-манифест
`public/assets/manifest.json` + `compute_asset_path`.

### Sanitize (P2)
`sanitize, strip_tags, strip_links` — нужен HTML-парсер (lexbor).

### Fragment cache (P2)
`cache do ... end` / `cache_if / cache_unless`, Russian-doll ключи из
MD5-дайджеста исходника шаблона (dependency-tracker по `render`-вызовам).

## Реализация

- ECR-компиляция в методы-рендеры при сборке (`ECR.def_to_s`-паттерн);
  view-контекст = класс с миксинами модулей хелперов.
- FormBuilder — статический набор методов (в Rails они тоже генерятся
  один раз CodeGenerator'ом).
- CSRF-токен в формах — как в Rails (authenticity_token).

## Фазы

- P0: ECR + layouts/partials, content_for, тег/контент/текст/числа/URL-хелперы.
- P1: form_with/FormBuilder полный, tag-хелперы, assets, csrf.
- P2: sanitize (lexbor), fragment cache, полиморфные url, collection
  counter/iteration хвосты.

## Готово, когда

форма из Rails-туториала (`form_with model: @post` + `f.text_field :title`
+ `f.submit`) рендерится байт-в-байт тем же HTML (id/name-конвенции
`post[title]`, authenticity token).

## Зависимости

active_support.cr, action_pack.cr (routes/params), lexbor (P2).
