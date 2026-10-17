# CIRCULAR_DEPENDENCIES_ISSUE

Дата: 2026-10-17. Статус: закатано релизами (см. «Что сделали»), системная
проблема — нет. Этот файл — чтобы при следующем минорном релизе base-шарда
не наступить на те же грабли.

## Симптом

Docker-сборка once-campfire-crails падала на первом же компайле:

```
In config/routes.cr:13:3

 13 | resource :first_run, only: [:show, :create]
     ^-------
Error: undefined method 'resource' for CRails::Routes::Drawer
```

Локально при этом приложение собиралось.

## Корневая цепочка

1. `resource` (singular) и весь Rails-style роутинг-DSL появились только в
   **action_pack.cr v0.2.0** (коммит `4cd1f05`, тег запушен). Первый простой
   `def resources` — ещё `4dd3a89` (монорепо, Iteration 13).
2. Но **все** потребители action_pack в экосистеме пинили его верхней
   границей `~>`:

   | шард                | версия/ HEAD | требовал action_pack_cr |
   |---------------------|--------------|-------------------------|
   | railties_cr         | 0.1.10       | `~> 0.1.3` (< 0.2.0)    |
   | action_cable_cr     | 0.1.1        | `~> 0.1.0` (< 0.2.0)    |
   | turbo_cr            | 0.1.1        | `~> 0.1.0`              |
   | active_storage_cr   | master       | `~> 0.1.0`              |
   | jbuilder_cr         | main         | `~> 0.1.0`              |

   Резолвер shards обязан удовлетворить ВСЕХ, поэтому любой минорный
   бамп action_pack обязан выходить **одновременно** с релизами всех
   пятерых зависимых. Это и есть псевдоциккл: шарды друг от друга не
   зависят по коду, но связаны жёсткими верхними границями по версиям —
   lockstep-релизы без инструмента, который бы их делал.
3. Локальная сборка это маскировала: `lib/action_pack_cr` в приложении был
   подменённой копией — код v0.2.0, а в `shard.yml` подписан `0.1.3`.
   Версия совпадала с lock, shards не переустанавливал, компилятор видел
   `resource`. Docker же честно ставил 0.1.3 с GitHub.
4. Доп. фактор: shards кэширует git-refs в `~/.cache/shards/github.com/...`
   и после пуша новых тегов резолвер мог ещё долго не видеть их (лечится
   `git fetch --force` в кэш-репо или удалением кэша).

## Что сделали (2026-10-17)

- `railties_cr v0.1.11`: dep `action_pack_cr ~> 0.2.0` + страницы ошибок из
  `public/#{status}.html` (PublicExceptionsController-порт; фича до этого
  жила только в `lib/railties_cr` приложения — ещё один источник
  расхождения локальной и Docker-сборки).
- Релиз 0.1.11 перенесён обратно в монорепо (2026-10-17, позже тем же
  днём): `shard.yml` (версия + `~> 0.2.0`), public-error-pages в
  `middleware.cr` (в development поверх них — DebugExceptions-страницы),
  спеки `csrf_spec` (8.2 Sec-Fetch-Site стратегии) и `log_level_spec`.
  До этого монорепо сидела на 0.1.10/`~> 0.1.3` — следующая публикация
  из неё молча откатила бы релиз. Чекаут публикации railties в
  `~/myshards/` отсутствует — релиз делался из временной копии.
- `action_cable_cr v0.1.2`, `turbo_cr v0.1.3`, `active_storage_cr v0.1.1`,
  `jbuilder_cr v0.1.0`: констрейнт action_pack ослаблен до `>= 0.1.0`
  (floor без верхней границы).
- Приложение: active_storage/jbuilder переведены с веток на теги,
  lock перегенерён, `crystal build src/app.cr` и `shards install` без
  локального `shard.override.yml` проверены.

## Как чинить системно (TODO)

1. **Политика констрейнтов.** Внутриэкосистемные base-шарды
   (action_pack, active_support, active_record) зависимые объявляют как
   `>= X.Y.Z` без верхней границы — доверяем semver-тегам. `~>` оставляем
   только для внешних шардов (db, pg, redis, bcrypt). Тогда минорный бамп
   base-шарда перестаёт требовать синхронного релиза всех.
2. **Скрипт lockstep-релиза** (`rake publish[shard,version]` в монорепо):
   бампает версию, прогоняет спеки, коммитит, тегует, пушит ветку+тег,
   затем `git ls-remote`-ом проверяет, что тег виден на remote, и только
   потом идёт к зависимым. Заодно решает проблему stale-кэша shards
   (п. 4 выше) — паблишер сам ждёт видимости тега.
3. **Запрет подмены `lib/`.** Расхождение «код из ветки, версия из тега»
   в `lib/` — именно то, что скрыло проблему. Правило: lib/ либо честный
   `shards install`, либо path-деп в `shard.override.yml`, никогда
   ручное копирование. Проверять в CI: свежий clone → `shards install`
   → `crystal build` (то, что делает Docker-образ) перед пушем.
4. **Тегировать каждый релиз сразу.** В процессе нашлись брошенные:
   turbo v0.1.2 (коммит запушен, тег нет), active_storage v0.1.1 и
   jbuilder v0.1.0 (TODO в shard.yml приложения висели неделю). Из-за
   этого приложение сидело на ветках `master`/`main` — плавающие HEAD,
   невоспроизводимые сборки.

## Справка: где что живёт

- Монорепо (эти шарды как подкаталоги): `~/rails.cr/`, remote
  `git@github.com:OrelSokolov/crails.git`.
- Публикуемые standalone-репо: `github.com/OrelSokolov/<name>.cr.git`
  (railties, action_pack, action_cable, turbo, active_storage, jbuilder, ...).
- Рабочие чекауты публикаций: `~/myshards/<name>.cr`.
- Потребитель, на котором всё всплыло: `~/once-campfire-crails`
  (`github.com/OrelSokolov/once-campfire-crails`), Docker-образ ставит
  шарды через `shards install` из lock, без path-копий.
