# active_record.cr — порт ActiveRecord

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActiveRecord` — 1:1. Оценка: ~90% (детальный отчёт:
`/home/oleg/egui.cr/plans/crails-api-research.md`).

**Статус (2026-10-02): read-срез P0 готов и проверен на реальной базе
пользователя (`data_lake_development`): кодоген атрибутов из schema.yml,
Relation (where/not/order/limit/first/count/pluck/find_each/find_by),
подключение (URL / Rails-config / database.yml, unix-сокеты,
schema_search_path). Спеки: 29 (fixtures + datalake read-only). См.
`README.md`. Запись, валидации, ассоциации, миграции — следующие фазы.

## Цель

Слой работы с БД без ощущения «я ушёл с Rails»: модели, валидации,
ассоциации, скопы, коллбэки, миграции — те же имена, kwargs и цепочки.
PostgreSQL (crystal-pg) в первой итерации.

## Ключевой механизм: кодоген атрибутов

Rails генерит `name`, `name=`, `name?`, `name_was`, `name_changed?` по
схеме БД в рантайме (`define_method`). Crystal-эквивалент —
compile-time кодоген: `{{ run("codegen/from_schema.cr", table) }}` читает
`db/schema.yml` и сплайсит def-ы в тело класса (проверено зондом).
`db/schema.yml` генерится командой `crails db:schema:dump` (или миграциями).

## API 1:1

### Ассоциации (P1)
`belongs_to / has_many / has_one / has_and_belongs_to_many` со всеми
опциями (`class_name, foreign_key, dependent, through, source,
polymorphic, counter_cache, inverse_of, validate, autosave, touch,
optional, primary_key`); генерятся `author`, `author=`, `build_author`,
`create_author`, `post_ids`, CollectionProxy (`build, create, <<, concat,
delete, destroy, destroy_all, empty?, size, include?, replace`).

### Валидации (P0)
`validates :name, presence: true, length: {minimum: 2}, format:,
numericality:, inclusion:, exclusion:, acceptance:, confirmation:,
comparison:, uniqueness: {scope:}, if:/unless:/on:/allow_nil:/
allow_blank:/strict:` (kwargs через `**opts`); `validate do ... end`;
`errors.add/full_messages/details/where/group_by_attribute`;
`valid?/invalid?`.

### Коллбэки (P0)
`before/after/around_validation|save|create|update|destroy`,
`after_initialize, after_find, after_touch, after_commit, after_rollback`
(+ `_commit`-варианты) — макросы, статический упорядоченный список.

### Скопы и запросы (P0–P1)
`scope :published do ... end` (сплайс тела блока — проверено),
`default_scope, unscoped`. Relation:
`where(**), where("age > ?", 1), not, or, order(hash/args/sql), reorder,
in_order_of, limit, offset, group, having, distinct, select, reselect,
deselect, joins, left_outer_joins, includes, preload, eager_load,
references, find, find_by(**), find_by!, find_or_create_by,
first_or_create, take/first/last/sole, exists?, count/sum/average/
minimum/maximum, pluck, pick, ids, find_each, find_in_batches,
in_batches, update_all, delete_all, destroy_all, insert_all, upsert_all,
touch_all, none, except/only, merge, strict_loading, annotate, explain,
lock, readonly`.

### Persistence + dirty (P0–P1)
`new, create, create!, save, update, update!, update_attribute,
update_columns, assign_attributes, attributes, increment/decrement(+!),
toggle, touch, destroy, delete, becomes, reload, persisted?,
new_record?, changed?, changes, saved_changes, previous_changes,
will_save_change_to?, restore_attributes, transaction (requires_new:,
isolation:), with_lock, lock!`.

### Миграции (P1)
`create_table do |t| t.string/t.integer/t.bigint/t.float/t.decimal/
t.datetime/t.time/t.date/t.text/t.boolean/t.binary/t.json/t.jsonb/
t.uuid, t.timestamps, t.references (polymorphic:), t.index (unique:,
where:, name:)`, `change_table, add_column, remove_column, rename_column,
change_column, change_column_default, change_column_null, add_index,
add_foreign_key, add_reference, create_join_table, add_check_constraint,
drop_table, reversible, up/down/change, execute`; реверс `change` через
command recorder. Формат: `db/migrate/*_create_posts.cr`.

### Прочее (P1–P2)
`enum status: [:draft, :published]` → `draft?/draft!` + скопы (макрос);
`serialize`, `store/store_accessor`, `alias_attribute`, `attribute :x,
default:`, `accepts_nested_attributes_for (+ _destroy, reject_if)`,
`counter_cache` конвенции, `cache_key/to_param`, `signed_id`,
`has_secure_token`, STI (`type`-колонка, `becomes` — dispatch через
compile-time registry `{{ @type.all_subclasses }}`), `table_name=`,
`primary_key=`, `attr_readonly`.

## Реализация

- Relation — иммутабельные value-объекты (WHERE-дерево + builder SQL),
  как в Rails; классовый уровень делегирует на `all`.
- Пул коннектов на fiber'ах (crystal-pg, `DB::Pool`).
- `{{ run }}`-кодоген из schema.yml; после миграций — перекомпиляция
  (dev-цикл: `crails db:migrate && crails watch`).

## Фазы

- P0: кодоген атрибутов, CRUD, валидации, коллбэки, базовый Relation
  (where/order/limit/find/pluck/count), transaction.
- P1: ассоциации (belongs_to/has_many/has_one, :through), скопы,
  полные запросы, миграции + `crails db:*`.
- P2: HABTM, STI/polymorphic-хвост, enum/store/nested attributes,
  eager loading, optimistic locking.

## Готово, когда

Рельс-учебниковская модель (`Post` с `belongs_to :user`,
`validates :title, presence: true`, `scope :published`) и контроллер
CRUD работают кодом 1:1 с Rails-туториалом.

## Зависимости

active_support.cr, crystal-pg.
