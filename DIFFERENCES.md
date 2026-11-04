# DIFFERENCES — semantic and API differences from Ruby on Rails

> Practical differences that everyone coming from Ruby runs into.
> These are consequences of Crystal's static typing: errors that Rails
> catches at runtime (or never catches at all) are caught here by the
> compiler.

## 0. The basics

A full clone of the Ruby on Rails API on Crystal, as 1:1 as possible
in the end interface — so that a developer moving from Ruby/Rails feels
no difference. Goal: Rails application code ports to Crystal nearly
verbatim.

**The only namespace difference: `CRails` instead of `Rails`.**

- `CRails.application`, `CRails.env`, `CRails.root`, `CRails.logger` —
  as `Rails.*` was in Rails.
- ERB → ECR (the only visible substitution — the language is different).
- Commands: `crails` instead of `rails` (`crails new`, `crails server`,
  `crails generate`, `crails console`, `crails routes`,
  `crails db:migrate`).

## 1. Nilable finders cannot be chained

In Rails `User.where(...).first.update(...)` works as long as the
record exists; when it doesn't — `NoMethodError` on `nil` at runtime.

In Crystal `first`/`take`/`last`/`find_by` are declared as `T?`
(`User | Nil`). Calling any `User` method on a nilable type is a
**compile-time** error, not a runtime one:

```crystal
User.where(email: "a@b.c").first.update({"language" => "en"})
# Error: undefined method 'update' for Nil (compile-time type is (User | Nil))
```

Printing a nilable value (`first` in the console, `.count`,
`.exists?`) works; chaining does not. This is deliberate design:
the compiler won't let you write a path where `nil.update` is
possible.

### How to do it right

```crystal
# 1. Bangs — a missing record is considered an error (RecordNotFound)
User.where(email: "...").first!
User.find_by!(email: "...")

# 2. not_nil! — same, but the exception comes from stdlib
User.where(email: "...").first.not_nil!

# 3. try — silently skips nil (the Ruby &. analogue)
User.where(email: "...").first.try(&.update({"language" => "en"}))

# 4. if-assignment — the idiomatic variant
if u = User.where(email: "...").first
  u.update({"language" => "en"})
end

# 5. Mass update without loading the record
User.where(email: "...").update_all({"language" => "en"})
```

Signatures (relation.cr / base.cr): `first/take/last/find_by/find?` →
`T?`; `first!/sole/find_by!/find` → `T`.

## 2. Type narrowing — why `if u = ...` helps

A plain assignment does not change the type: `u = ...first` gives
`u : User?`, and `u.update` still won't compile. But inside the branch

```crystal
if u = User.where(...).first
  u.update({"language" => "en"})  # here u : User
end
```

the compiler narrows the type (type narrowing): only truthy values
enter the `if` branch, `nil` is always falsey, so inside the branch
`u` is `User`. After leaving the `if` the type is `User?` again.
With `not_nil!`/`first!` no narrowing is needed — their *static* type
is `T` right away (the check moves to a runtime exception).

## 3. Keyword arguments are not packed into a Hash automatically

In Ruby `update(password: "x")` is `update({password: "x"})`. In
Crystal it is not: a method without a `**` parameter won't accept
keywords.

- Query API (`where`/`not`/`order`/``find_by`` etc.) accepts keywords —
  there are explicit `**opts` overloads.
- Persistence API (`update`/`update!`/`update_attribute`/
  `update_columns`/`create`/`new`) accepts **only
  `Hash(String, Value)`**:

```crystal
u.update({"language" => "en"})        # yes
u.update(language: "en")              # no, won't compile
```

## 4. assign_attributes only knows real columns

`assign_attributes` (and everything that goes through it: `update`,
`create`, `new(**attrs)`) is generated from the DB schema and raises
`ArgumentError: unknown attribute ... for User` on an unknown key.
Virtual attributes of gems (e.g. devise's `password`) cannot be
assigned through a hash — only via a direct setter:

```crystal
u = User.find_by!(email: "...")
u.password = "new-secret"   # devise setter: hashes into encrypted_password
u.save
```

The setter may contain arbitrarily complex gem logic, but you cannot
call it via `update({...})` — that is the price of compile-time code
generation from the schema.

## 5. Value unions and `.as()`: where Ruby gets by with duck typing

Results of "polymorphic" AR methods are union types, and must be
narrowed before use:

```crystal
relation.count        # Int64 | Hash(Value, Int64)  — plain and grouped
relation.count.as(Int64) == 0                        # see user.cr: ip_allowed?
relation.pluck("id")  # Array(Value)
relation.pick("email") # Value
```

`ActiveRecord::Value = Nil | Bool | Int64 | Float64 | String | Time |
JSON::Any | ...` (active_record_cr.cr). The same holds in models for
nullable attributes: `last_ip_update_at.as(Time)` (user.cr),
`st.as(Time) <= Time.utc` (activation_code.cr) — where Ruby would
simply write `st <= Time.utc`.

## 6. Crystal stdlib slaps a Rubyist's wrists

- **Division**: Ruby `10 / 3 == 3`; Crystal `10 / 3 == 3.333...`
  (`Int#/` returns Float64). Integer division is `10 // 3`. A quiet
  source of bugs when porting — the compiler does not catch it.
- **Overflow and Int sizes**: Ruby silently goes to Bignum; Crystal
  raises `OverflowError`. The literal `1` is `Int32`, a DB id is
  `Int64`; a runtime `Int32` is not converted implicitly — you need
  `.to_i64`.
- **Strings are immutable**: Ruby's `s << "x"` does not port — use
  `String.build { }`.
- **`&.` does not exist** — use `.try` (with a block) instead.
- **`h["key"]` / `a[10]` raise** KeyError/IndexError instead of
  returning nil as in Ruby. The quiet variant is `h["key"]?` and
  `a[10]?`. Also a runtime trap, not a compile error.
- **No runtime reflection**: `send`, `respond_to?`, `method_missing`,
  `define_method` — none of them exist. Idioms like
  `User.send(:find_by, ...)` cannot be ported at all;
  metaprogramming is done with compile-time macros (like the schema-
  driven attribute codegen from db/schema.yml).

## 7. The console (icr) is not irb

- Every line is a recompilation (~seconds per call in a large
  project), not an instant interpreter reply.
- Ruby object state does not persist between lines as in irb — every
  line is compiled on top of the session replay; DB side effects
  (`save`, `update_columns`) do persist, though.

---

The general principle: Rails semantics are preserved where it is safe
(returning `nil` instead of an exception from "quiet" finders — as in
Rails), but static types force you to handle `Nil` explicitly — right
away, not in production.
