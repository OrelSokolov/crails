# active_record.cr — план-таблица порта ActiveRecord

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.
>
> Неймспейс `ActiveRecord`, API 1:1 с Rails 8. Статус меняем прямо в этой
> таблице. Легенда статусов:
>
> - ✅ готово (покрыто спеками)
> - 🔶 частично (перечислено, чего не хватает в «Примечании»)
> - ⬜ не начато
> - ❌ Crystal не позволит / осознанное отклонение (эквивалент указан)

## Ключевой механизм

Rails генерит методы атрибутов в рантайме (`define_method`). Crystal-эквивалент
— compile-time кодоген `{{ run("codegen/from_schema.cr", table) }}` из
`db/schema.yml` (генерится `crails db:schema:dump` или миграциями; после
миграций — перекомпиляция, dev-цикл `crails db:migrate && crails watch`).

Универсальные Crystal-ограничения (влияют на строки с ❌):

- нет `method_missing` → никакой рантайм-магии методов;
- Symbol существует только compile-time → нет `constantize`/"to_sym" в рантайме;
- статическая типизация → нет неявных строково-числовых приведений.

Общий обходной приём — compile-time registry `{{ @type.all_subclasses }}`
(заменяет рантайм-резолв классов по строке/колонке `type`).

## 1. Подключение и схема

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `establish_connection` (URL / config / database.yml) | ✅ | да | `connection.cr` |
| Unix-сокеты, `schema_search_path` | ✅ | да | |
| Пул коннектов (fiber-safe) | ✅ | да | `DB::Pool` crystal-pg |
| Кодоген атрибутов `name / name= / name? / name_was / name_changed?` | ✅ | да | `{{ run }}`-кодоген вместо `define_method` |
| `table_name=`, `primary_key=` | 🔶 | да | есть `set_table_name`; `primary_key=` не сделан |
| `attribute :x, default:` | ⬜ | да | макрос + перегрузка типа |
| Рантайм-определение методов после смены схемы БЕЗ рекомпиляции | ❌ | нет | эквивалент: `crails watch` = rebuild |

## 2. Relation / запросы

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `where(**)`, `where("sql ?", args)` | ✅ | да | kwargs вместо рубишного hash-аргумента |
| `not`, `order`, `limit`, `offset`, `reverse_order` | ✅ | да | |
| `each, empty?, count, size, pluck, pick, ids` | ✅ | да | |
| `take, first, first!, last, sole, to_sql` | ✅ | да | |
| `exists?` | 🔶 | да | нет варианта `exists?(conditions)` |
| `find_each` | ✅ | да | |
| `find, find?, find_by, find_by!` | ✅ | да | на уровне класса |
| `first_or_create, find_or_create_by(_!)` | ✅ | да | |
| `sum / average / minimum / maximum` | ⬜ | да | |
| `or` | ⬜ | да | требует WHERE-дерево вместо текущего `Array(String)` — рефакторинг |
| `group, having, distinct, select, reselect` | ⬜ | да | |
| `joins, left_outer_joins` | ⬜ | да | строки/имена ассоциаций через registry |
| `includes, preload` | ⬜ | да | preload — отдельные запросы, просто |
| `eager_load, references` | ⬜ | да | LEFT OUTER JOIN + алиасы, сложнее |
| `reorder, in_order_of` | ⬜ | да | |
| `find_in_batches, in_batches` | ⬜ | да | |
| `update_all, delete_all, destroy_all, touch_all` | ⬜ | да | на уровне Relation (классовые `destroy/delete` есть) |
| `none, except/only, merge, annotate, explain` | ⬜ | да | |
| `lock, readonly, strict_loading` | ⬜ | да | `strict_loading` без рантайм-исключений — упрощённо |
| `scope :name do ... end` | ⬜ | да | сплайс тела блока — проверено зондом |
| `default_scope, unscoped` | ⬜ | да | |
| Dynamic finders `find_by_email` | ❌ | нет | нет `method_missing`; замена `find_by(email: ...)` |
| `where` с рантайм-строками как Symbol-ключами | ❌ | нет | только compile-time kwargs/строки |

## 3. Валидации

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `validates` presence / length / numericality / format / uniqueness | ✅ | да | `allow_nil` есть |
| `validate` (метод/блок) | ✅ | да | |
| `valid? / invalid?` | ✅ | да | |
| `errors.add / full_messages / where / size / empty?` | ✅ | да | |
| `inclusion, exclusion, acceptance, confirmation, comparison` | ⬜ | да | confirmation = кодоген виртуального `_confirmation`-атрибута |
| `uniqueness: {scope:}` | ⬜ | да | запрос в валидации |
| `if: / unless:` (Symbol, proc) | ⬜ | да | |
| `on: / allow_blank: / strict:` | ⬜ | да | |
| `errors.details / group_by_attribute` | ⬜ | да | |
| numericality: строка в Int-колонку проходит валидацию | ❌ | нет | не скомпилируется — отклонение задокументировано в oracle |

## 4. Коллбэки

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| before/after `_validation / _save / _create / _update / _destroy` | ✅ | да | метод или блок |
| `around_validation/save/create/update/destroy` | ⬜ | да | через `yield` |
| `after_initialize, after_find, after_touch` | ⬜ | да | |
| `after_commit, after_rollback` (+ `_create/_update/_destroy`) | ⬜ | да | реестр коллбэков внутри транзакции; зависит от §7 |

## 5. Ассоциации

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `belongs_to` (+ `build_/create_/create_`) | ✅ | да | опции: `foreign_key, class_name, optional` |
| `has_many` (+ `dependent`) | ✅ | да | опции: `dependent, foreign_key, class_name` |
| `has_one` (+ `build_/create_`, `dependent`) | ✅ | да | |
| CollectionProxy `each/count/size/empty?/ids/pluck/build/create/create!/destroy_all/delete_all/order?/where?` | ✅ | да | |
| CollectionProxy `<< / concat, delete, destroy, include?, replace` | ⬜ | да | |
| `post_ids` | ⬜ | да | |
| `through / source` | ⬜ | да | |
| polymorphic (`as:`, `imageable_type`) | ⬜ | да | резолв класса по строке — compile-time registry строка→класс |
| `has_and_belongs_to_many` | ⬜ | да | |
| `counter_cache` (опция + conventional) | ⬜ | да | |
| `inverse_of, autosave, touch, primary_key, validate` (опции) | ⬜ | да | |
| Рантайм `class_name: "Foo"` по любой строке | ❌ | частично | только классы, известные на компиляции (registry) |

## 6. Persistence + dirty

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `new, create(_!), save(_!), update(_!), assign_attributes, attributes` | ✅ | да | |
| `destroy, persisted?, new_record?, frozen?` | ✅ | да | |
| dirty: `changed?/changed/changes/saved_changes/has_changes_to_save?/will_save_change_to_x?` | ✅ | да | |
| `update_columns, touch, touch(*cols)` | ✅ | да | |
| `insert_all, insert_all!, upsert_all` | ✅ | да | |
| `reload` | 🔶 | да | кодоген даёт `reload!`; нужен каноничный `reload` |
| `update_attribute, increment/decrement(+!), toggle` | ⬜ | да | |
| `restore_attributes, previous_changes` | ⬜ | да | |
| инстансный `delete` | ⬜ | да | |
| `becomes` | ⬜ | да | через compile-time registry; произвольный класс в рантайме — нет |
| `delete`/`destroy` класса по id, `update(id, ...)` | ✅ | да | |

## 7. Транзакции и локи

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `transaction` (блок), `requires_new:, isolation:` | ⬜ | да | crystal-pg поддерживает; заявлено в P0 — главный долг |
| `with_lock, lock!` | ⬜ | да | |
| optimistic locking (`lock_version`) | ⬜ | да | |

## 8. Миграции

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `create_table` (все типы колонок, `timestamps, references, index`) | ✅ | да | |
| `drop_table, add/remove/rename/change_column, change_column_default/null` | ✅ | да | |
| `add_index (unique:, name:), remove_index` | ✅ | да | `where:`-индексы не проверены |
| `add_reference / add_belongs_to, add/remove_foreign_key` | ✅ | да | |
| `execute`, реверс `change` (command recorder) | ✅ | да | |
| `crails db:migrate / rollback / schema:dump` (schema.yml) | ✅ | да | |
| `change_table` | ⬜ | да | |
| `create_join_table` | ⬜ | да | |
| `add_check_constraint` (+ remove) | ⬜ | да | |
| `reversible` (полный) / `up/down` | 🔶 | да | recorder есть; `reversible`-блоки не сделаны |
| `t.index (where:)` | 🔶 | да | DSL-параметр есть, генерация частичного индекса не проверена |

## 9. Прочее (P2)

| API (Rails) | Статус | Crystal? | Примечание |
|---|---|---|---|
| `enum status: [...]` → `draft?/draft!` + скопы | ⬜ | да | макрос |
| `serialize` | ⬜ | да | JSON-кодек |
| `store / store_accessor` | ⬜ | да | макрос |
| `alias_attribute` | ⬜ | да | макрос-делегация |
| `accepts_nested_attributes_for` (+ `_destroy, reject_if`) | ⬜ | да | сложный макрос |
| `cache_key / to_param` | ⬜ | да | |
| `signed_id` | ⬜ | да | OpenSSL |
| `has_secure_token` | ⬜ | да | |
| STI (колонка `type`) | ⬜ | да | dispatch через `{{ @type.all_subclasses }}` |
| `attr_readonly` | ⬜ | да | |
| Рантайм-`constantize` по строке | ❌ | нет | только compile-time registry |

## Порядок работ

1. **P0-долг**: транзакции (§7) → `after_commit/rollback` (§4).
2. **P1**: скопы + агрегаты + `or`-рефакторинг WHERE-дерева (§2) → хвост
   валидаций (§3) → `around_*`-коллбэки (§4) → доп. опции ассоциаций и
   CollectionProxy (§5) → хвост persistence (§6) → хвост миграций (§8).
3. **P2**: eager loading, `through`/polymorphic/HABTM, STI, enum/store,
   nested attributes, optimistic locking (§2, §5, §9).

## Готово, когда

Рельс-учебниковская модель (`Post` с `belongs_to :user`,
`validates :title, presence: true`, `scope :published`) и контроллер CRUD
работают кодом 1:1 с Rails-туториалом.

## Тестирование (правило AGENTS.md)

Каждая фича начинается с интеграционных кейсов: oracle/cases.rb +
oracle/migrations.rb сняты с настоящего activerecord 8.1.4; обе реализации
проходят одни тесты без правки тестов. Задокументированные отклонения —
только строки с ❌ выше.

## Зависимости

active_support.cr, crystal-pg.
