# SEMANTICS — отличия семантики и типов от Ruby on Rails

> Практические отличия, на которые наступает каждый, кто пришёл из Ruby.
> Речь о следствиях статической типизации Crystal: ошибки, которые в
> Rails ловятся в рантайме (или не ловятся вовсе), здесь ловит компилятор.

## 1. Nilable-файндеры нельзя разворачивать в цепочку

В Rails `User.where(...).first.update(...)` работает, пока запись есть;
когда её нет — `NoMethodError` на `nil` в рантайме.

В Crystal `first`/`take`/`last`/`find_by` объявлены как `T?`
(`User | Nil`). Вызов любого метода `User` на nilable-типе — **ошибка
компиляции**, а не рантайма:

```crystal
User.where(email: "a@b.c").first.update({"language" => "en"})
# Error: undefined method 'update' for Nil (compile-time type is (User | Nil))
```

Печать nilable-значения (`first` в консоли, `.count`, `.exists?`) —
работает; разворачивание в цепочку — нет. Это осознанный дизайн:
компилятор не даёт написать путь, где возможен `nil.update`.

### Как правильно

```crystal
# 1. Банги — отсутствие записи считается ошибкой (RecordNotFound)
User.where(email: "...").first!
User.find_by!(email: "...")

# 2. not_nil! — то же, но исключение из stdlib
User.where(email: "...").first.not_nil!

# 3. try — молча пропустит nil (аналог Ruby &.)
User.where(email: "...").first.try(&.update({"language" => "en"}))

# 4. if-присваивание — идиоматичный вариант
if u = User.where(email: "...").first
  u.update({"language" => "en"})
end

# 5. Массовое обновление без загрузки записи
User.where(email: "...").update_all({"language" => "en"})
```

Сигнатуры (relation.cr / base.cr): `first/take/last/find_by/find?` → `T?`;
`first!/sole/find_by!/find` → `T`.

## 2. Type narrowing — почему `if u = ...` помогает

Простое присваивание тип не меняет: `u = ...first` даёт `u : User?`,
и `u.update` так же не скомпилируется. Но внутри ветки

```crystal
if u = User.where(...).first
  u.update({"language" => "en"})  # здесь u : User
end
```

компилятор сужает тип (type narrowing): в ветку `if` попадают только
truthy-значения, `nil` всегда falsey, значит внутри ветки `u` — `User`.
После выхода из `if` тип снова `User?`. У `not_nil!`/`first!` сужение
не нужно — их *статический* тип сразу `T` (проверка переносится в
рантайм-исключение).

## 3. Кейворд-аргументы не пакуются в Hash автоматически

В Ruby `update(password: "x")` — это `update({password: "x"})`. В
Crystal — нет: метод без `**`-параметра кейворды не примет.

- Query-API (`where`/`not`/`order`/``find_by`` и т.п.) принимает
  кейворды — там есть явные `**opts`-оверлоады.
- Persistence-API (`update`/`update!`/`update_attribute`/
  `update_columns`/`create`/`new`) принимает **только
  `Hash(String, Value)`**:

```crystal
u.update({"language" => "en"})        # да
u.update(language: "en")              # нет, не скомпилируется
```

## 4. assign_attributes знает только реальные колонки

`assign_attributes` (и всё, что через него: `update`, `create`,
`new(**attrs)`) генерируется по схеме БД и на неизвестном ключе бросает
`ArgumentError: unknown attribute ... for User`. Виртуальные атрибуты
гемов (например, devise-`password`) через хэш не присвоить — только
прямым сеттером:

```crystal
u = User.find_by!(email: "...")
u.password = "new-secret"   # devise-сеттер: захеширует в encrypted_password
u.save
```

Внутри сеттера может быть сколь угодно сложная логика гема, но вызвать
её через `update({...})` нельзя — это цена compile-time кодогена по
схеме.

## 5. Value-union и `.as()`: где Ruby обходится duck-typing

Результаты «полиморфных» методов AR — union-типы, и перед использованием
их надо сузить:

```crystal
relation.count        # Int64 | Hash(Value, Int64)  — обычный и групповой
relation.count.as(Int64) == 0                        # см. user.cr: ip_allowed?
relation.pluck("id")  # Array(Value)
relation.pick("email") # Value
```

`ActiveRecord::Value = Nil | Bool | Int64 | Float64 | String | Time |
JSON::Any | ...` (active_record_cr.cr). В моделях то же самое с nullable-
атрибутами: `last_ip_update_at.as(Time)` (user.cr), `st.as(Time) <= Time.utc`
(activation_code.cr) — там, где Ruby написал бы просто `st <= Time.utc`.

## 6. Stdlib Crystal, бьёт по рукам рубиста

- **Деление**: Ruby `10 / 3 == 3`; Crystal `10 / 3 == 3.333...` (`Int#/`
  возвращает Float64). Целочисленное — `10 // 3`. Тихий источник багов
  при порте — компилятор не ловит.
- **Переполнение и Int-размеры**: Ruby молча уходит в Bignum; Crystal
  кидает `OverflowError`. Литерал `1` — `Int32`, id из БД — `Int64`;
  рантаймовый `Int32` не конвертится неявно — нужен `.to_i64`.
- **Строки неизменяемые**: `s << "x"` из Ruby не портируется —
  `String.build { }`.
- **`&.` не существует** — вместо него `.try` (с блоком).
- **`h["key"]` / `a[10]` бросают** KeyError/IndexError, а не возвращают
  nil, как в Ruby. Тихий вариант — `h["key"]?` и `a[10]?`. Тоже
  рантайм-ловушка, не ошибка компиляции.
- **Нет рантайм-рефлексии**: `send`, `respond_to?`, `method_missing`,
  `define_method` — нет. Идиомы вроде `User.send(:find_by, ...)` не
  портируются в принципе; метапрограммирование — compile-time макросами
  (как кодоген атрибутов по db/schema.yml).

## 7. Консоль (icr) — не irb

- Каждая строка — перекомпиляция (~единицы секунд на вызов в большом
  проекте), а не мгновенный ответ интерпретатора.
- Состояние Ruby-объектов между строками не живёт как в irb — каждая
  строка компилируется поверх реплея сессии; зато эффекты в БД
  (`save`, `update_columns`) остаются.

---

Общий принцип: семантика Rails сохраняется там, где это безопасно
(возврат `nil` вместо исключения у «тихих» файндеров — как в Rails),
но статические типы заставляют обработать `Nil` явно — сразу, а не
в продакшене.
