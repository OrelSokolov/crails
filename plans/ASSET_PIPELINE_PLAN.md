# ASSET PIPELINE — план полной реализации для CRails

Цель: закрыть единственную недостающую половину asset pipeline —
**сборку** (компиляция исходников в digest-файлы + манифест + прекомпрессия
+ CLI-таски + резолвинг путей во вьюхах). Отдача уже портирована
(`lib/railties_cr/src/static.cr`: ActionDispatch::Static 8.1.4 +
семантика Propshaft::Server), теги-хелперы есть (`action_view_cr`),
importmap-rails портирован (`importmap_cr`) — но ничто из этого не
соединено компилятором, и benchmark-приложение хардкодит digest-имена
в статических HTML-фрагментах, а сами файлы собирает Node-скрипт из
чужого репозитория (REPORT.md §2: без них preflight падает
`static_css: 404`).

Эталон порта — **propshaft 1.3.2** (та же версия, на которую уже
опирается `static.cr`): CRails сознательно выбрал propshaft-модель
(pass-through, без транспиляции/Sass), а не sprockets-модель.

Документ двухчастный:

- **Часть A (фазы 0–5)** — работа в монорепо фреймворка `crails`
  (новый каталог `propshaft_cr/` + правки в `action_view.cr/`,
  `importmap.cr/`, `railties.cr/`; пути ниже даны относительно
  корня монорепо, `lib/...`-форма соответствует дереву
  once-campfire-crails);
- **Часть B (фаза 6)** — интеграция в once-campfire-crails.

---

## 0. Что считаем эталонным поведением (фиксируется оракулом)

Точные wire-детали НЕ берутся из памяти — они пинятся оракулом
(см. фазу 0). Из исходников/репозитория уже известно и обязательны:

- digest — `Digest::SHA1.hexdigest(content)`, в имени файла
  усекается (в репо принято 8 hex-символов: `_reset-9c3efd7b.css`;
  regex стриппинга в `static.cr:209` — `-[0-9a-zA-Z]{7,128}`,
  процитирован из `Propshaft::Asset.extract_path_and_digest`).
  Точную длину в имени подтверждает оракул.
- манифест — `public/assets/.manifest.json`: JSON-хэш
  `logical path → digested path` (логический `landing.css` →
  `landing-<digest>.css`). Точный формат сериализации — оракул.
- load path — каждый подкаталог `app/assets/*` добавляет файлы по
  пути относительно себя (`app/assets/stylesheets/x.css` →
  logical `x.css`); при дубликатах logical path побеждает первый
  по алфавиту каталог (семантика уже реализована в
  `static.cr#resolve_propshaft_asset` — переиспользовать).
- компиляторы контента: CSS url()-rewrite с подстановкой digest
  (`Propshaft::Compiler::CssUrls`) и JS-аналог для
  `new URL("...", import.meta.url)` (`Propshaft::Compiler::JsAssetUrls`);
  всё остальное — pass-through. SRI/integrity — P2 (см. фазу 3).
- прекомпрессия: соседи `.gz` и `.br` рядом с digest-файлом —
  это CRails-требование (static.cr уже умеет их отдавать по
  Accept-Encoding); о том, что пишет сам propshaft 1.3.2 — сверить
  по оракулу, при расхождении делать оба.

## Часть A. Фреймворк

### Фаза 0 — оракул (propshaft 1.3.2)

Новая библиотека `lib/propshaft_cr` по образцу соседних портов
(`shard.yml`, `src/`, `spec/`, `oracle/`, `README.md`, `PLAN.md`).
В монорепо crails — каталог `propshaft_cr/` рядом с `importmap.cr`,
`railties.cr` и т.д.

Конвенции репозитория (AGENTS.md) обязательны:

- **oracle-first**: переписывание 1:1 начинается с интеграционных
  кейсов на оригинальном геме; ruby 3.4.5, rails 8.1.4 установлены;
  формат `oracle/*.yml` — строки `"case_id\tvalue"`;
- **реверс-проверка**: ruby-скрипт `oracle/verify_*.rb`, вызываемый
  из Crystal-спека через `Process.run` (паттерн:
  `active_support.cr/spec/crypto_oracle_spec.cr`);
- Crystal-спек зеркально воспроизводит те же case-ID;
- при необходимости оригинальные тесты гема подтягиваются
  дополнительно к синтетическим кейсам.

1. `oracle/propshaft_fixture/` — фикстурное дерево:

   ```
   app/assets/stylesheets/  (обычный css; css с url("bg.png"),
     url('../images/i.png'), url(без кавычек), @import)
   app/assets/images/       (png/svg)
   app/assets/javascripts/  (js с new URL("…", import.meta.url))
   ```

2. `oracle/propshaft_cases.rb` — Gemfile: `propshaft (= 1.3.2)`;
   прогон реального `Propshaft::Processor#process` на фикстурах:
   - список выходных файлов `public/assets/**` (имена с digest);
   - побайтовый контент переписанного CSS/JS;
   - побайтовый `.manifest.json`;
   - `Propshaft::Asset#digest`, `#fresh?`/`#stale?`, кейс дубликата
     logical path в двух load-path каталогах;
   - кейсы ошибок: отсутствующий в load path ассет
     (`Propshaft::MissingAssetError`).

3. `oracle/propshaft_expected.yml` — снимок вывода. Зеркало —
   `spec/propshaft_spec.cr`. Gate фазы: байт-в-байт совпадение
   manifest, digest-имён и переписанного контента.

### Фаза 1 — ядро `propshaft_cr`

`lib/propshaft_cr/src/`:

- `asset.cr` — `Propshaft::Asset`:
  - `logical_path : String`, `absolute_path : String`,
    `content : String` (лениво, с mtime-кэшем);
  - `digest : String` — SHA1 hexdigest **обработанного** контента;
  - `digested_path : String` — вставка `-<digest>` перед последним
    расширением (`x.css` → `x-<digest>.css`; файла без расширения —
    суффикс, сверьте с оракулом);
  - `fresh?(previous)`, `stale?(previous)` — сравнение digest
    (используется инкрементальной пересборкой и `assets:clean`);
  - `extract_path_and_digest(path)` — статический, тот же regex,
    что в `static.cr` (вынести константу в одно место —
    `static.cr` начинает её реэкспортировать отсюда).
- `load_path.cr` — `Propshaft::LoadPath`: коллекция каталогов;
  `assets : Hash(String, Asset)` (logical → asset, первый каталог
  побеждает — та же семантика, что сейчас наивно в
  `static.cr#resolve_propshaft_asset`); `find(logical)`,
  `missing?`. Конкатенация load path'ов как в геме.
- `compiler.cr` — `Propshaft::Compiler` + реестр:
  - `CssUrls` — regex-проход (пинн точного regex по оракулу),
    резолвит относительные url/@import через load path и
    подставляет digested-путь; нерезолвимое — оставить как есть
    (поведение гема — подтвердить оракулом, есть кейс);
  - `JsAssetUrls` — аналог для `new URL("<относит>", import.meta.url)`;
  - `Passthrough` — по умолчанию для прочих типов;
  - применение: `Compiler.new(load_path).compile(asset)` —
    компилятор решает по расширению.
- `manifest.cr` — `Propshaft::Manifest`: чтение/запись
  `.manifest.json`; `lookup(logical) : String?`,
  `lookup!(logical)` (raise `MissingAssetError` — сообщение 1:1
  с гемом, снять в оракул).
- `processor.cr` — `Propshaft::Processor`:
  `#process(output_path: public/assets, versions: [".gz", ".br"])`:
  1. для каждого asset load path: скомпилировать контент →
     посчитать digest → записать `public/assets/<digested_path>`;
  2. версии: `.gz` — `Compress::Gzip::Writer` (stdlib, уровень
     по умолчанию); `.br` — шарп `OrelSokolov/brotli.cr` (биндинги
     libbrotli, клон: ~/workspace/brotli.cr) либо внешний `brotli`
     CLI; если недоступно — пропустить без ошибки (static.cr
     отдаёт только существующие);
  3. записать `.manifest.json` (побайтово как в геме);
  4. инкрементальность: существующие файлы с тем же digest не
     перезаписывать (сравнение по имени);
  5. возвратить manifest.
  НЕТ здесь: удаление старых версий — это `clean` (фаза 2).

### Фаза 2 — конфигурация, railties-wiring, CLI-таски

**Конфиг** (`config/application.cr`, дефолты в railties):

```crystal
# Propshaft-дефолты:
config.assets.paths        = ["app/assets/images", "app/assets/javascripts",
                              "app/assets/stylesheets"] # + vendor/javascript (для importmap-пинов)
config.assets.prefix       = "/assets"
config.assets.server       = true   # dev: static.cr-resolver
config.assets.compilers    = [...]  # реестр из фазы 1
config.assets.versions     = [".gz", ".br"]
config.assets.precompile   = [] of String  # доп. logical paths (glob), как у propshaft
config.assets.excluded_paths = [] of String
```

**CLI** (`lib/railties_cr/src/cli.cr`, по образцу `db_tasks.cr`;
таска генерирует mini-runner `tmp/assets_runner.cr`, т.к. load path
берётся из конфига приложения):

```
crails assets:precompile   # Processor#process + отчёт (n assets, m skipped)
crails assets:clean        # удалить digest-версии, не входящие в текущий manifest
crails assets:clobber      # rm -rf public/assets + .manifest.json
```

Плюс в `Dockerfile`-конвенции `crails new` (фаза 5) — precompile
перед release-сборкой.

**Отдача (уже есть — только сверить):** production-режим
`CRails::Middleware::Static` продолжает отдавать `public/assets/*`
как обычную статику (digest-файлы, прекомпрессия, immutable);
dev-режим — resolver из `static.cr` по `app/assets` без сборки.
Сделать `@assets_root` настраиваемым из `config.assets.*` и
переиспользовать `Propshaft::LoadPath` вместо локального
`Dir.glob` (единая семантика дубликатов/первенства каталогов).

### Фаза 3 — резолвинг во вьюхах (`action_view_cr` + `importmap_cr`)

1. `action_view_cr/src/helpers/asset_tag_helper.cr` —
   `compute_asset_path` (сейчас: плоские `/stylesheets/<s>.css`,
   комментарий «Fingerprints/manifests come later (P1)»):
   - если манифест загружен — `Manifest#lookup!` и вернуть
     `/assets/<digested>`;
   - иначе (dev) — логический путь `/assets/<logical>` (отдаст
     static-резолвер);
   - отсутствующее в манифесте → raise `MissingAssetError`
     (паритет с Rails/propshaft; закрывает отклонение, записанное
     в `importmap_cr/PLAN.md`: «резолвер не падает на отсутствующих
     файлах»).
2. `importmap_cr/src/map.cr` — `AssetResolver#path_to_asset`
   (сейчас стаб `→ /javascripts/<path>`) переключить на
   `compute_asset_path` вью-контекста; тогда пины с манифестом
   резолвятся в `/assets/...-<digest>.js`, без манифеста —
   `/assets/<logical>.js` (dev), а `/javascripts/*` из
   `app/javascript` остаётся для unpinned-файлов.
   Oracle importmap'а переснять с резолвером-стабом И с
   резолвером-манифестом — двойной набор кейсов.
3. P2 (теперь реализуемо): SRI-integrity из
   `importmap_cr/PLAN.md` — `enable_integrity!` считает
   sha256+sha384 из контента asset'а через load path/манифест;
   поле `integrity` в importmap JSON. Гейт: oracle-кейсы
   `integrity:` с настоящим importmap-rails.

### Фаза 4 — паритет dev/prod и «ловушки»

- Тест-scenario: одно и то же приложение в dev (resolver) и
  prod (precompiled) отдаёт байт-одинаковые тела по
  байт-одинаковым logical-путям; заголовки — по static.cr
  (immutable/ETag/Vary — уже есть).
- `.map` (sourcemaps) проходят pass-through и попадают в
  манифест (поведение propshaft — подтвердить оракулом).
- Отклонения от гема, которые оформить в `propshaft_cr/PLAN.md`
  сразу (обновлять по ходу):
  - `draw`-подобный руби-DSL невозможен — конфиг через
    `config.assets.*` (как принято в CRails);
  - `.br`-прекомпрессия — не частью гема, CRails-расширение
    (шарп brotli.cr / CLI-brotli, опционально);
  - предустановленных CDN/`asset_host` — нет (можно добавить
    `config.action_controller.asset_host` отдельно, вне скоупа);
  - многопроцессорный `Processor#process` (parallel гема) —
    однопоточно (Crystal-фиберы при желании, но объём мал).

### Фаза 5 — генераторы и `crails new`

- `crails new` создаёт `app/assets/{stylesheets,javascripts,images}`
  и layout с `<%= stylesheet_link_tag "application" %>` +
  `<%= javascript_importmap_tags %>`;
- генератор `crails g controller/scaffold` кладёт
  `app/assets/stylesheets/<name>.css` (как Rails);
- README приложения упоминает `crails assets:precompile` в CI.

## Часть B. Интеграция в once-campfire-crails

### Фаза 6 — убрать хардкод и внешнюю зависимость

1. **Убрать статический хардкод digest'ов**:
   `app/views/stylesheets.html` (31 hardcoded `<link>`) и
   `app/views/importmap.html` (210 строк hardcoded map),
   вшитые через `{{ read_file }}` в `app/helpers/chat_layout.cr:5-6`:
   - перенести исходники CSS в `app/assets/stylesheets/`;
   - CSS-файлы с `url(...)` — перепишет CssUrls;
   - JS-модули (stimulus/turbo/trix/actioncable/highlight.js/
     lexxy) —vendored в `vendor/javascript` + пины в
     `config/importmap.cr` (importmap-модель, без Node-бандла),
     либо (менее предпочтительно) один раз скачать выход
     `build-assets.js` в `vendor/javascript` — фреймворк digest'ит
     их как есть;
   - layout рендерит `stylesheet_link_tag ...` и
     `javascript_importmap_tags` (фаза 3) — digest-имена берутся
     из манифеста.
2. **Сборка образа**: в `bin/docker-build.sh`/`Dockerfile` —
   стадия `crails assets:precompile` (в build-стадии, до release);
   `.gitignore`-комментарий про копирование из
   once-campfire-express удалить.
3. **Приёмка фазы 6** (критерии из REPORT.md §2):
   - `git clone` на чистую машину → `bin/docker-build.sh` →
     образ поднимается, `static_css` (и все ассет-ссылки) — 200,
     harness-preflight зелёный без ручных шагов;
   - правка одного CSS-файла → `crails assets:precompile` →
     новый digest в HTML без правки шаблонов и без пересборки
     в чужом репо;
   - медиа (`56k-67359aa6.mp3` и пр.) — через load path
     (`app/assets/audios` + `config.assets.paths`), digest
     сохраняется в manifest.

## Порядок и гейты

| Фаза | Результат | Гейт |
|---|---|---|
| 0 | oracle propshaft 1.3.2 | снимок зафиксирован |
| 1 | `propshaft_cr` ядро | spec = oracle байт-в-байт |
| 2 | CLI + конфиг + railties | precompile/clean/clobber на demo-app |
| 3 | резолвинг в хелперах | oracle actionview/importmap дополнен |
| 4 | dev/prod паритет | сценарий A/B прогон |
| 5 | генераторы | `crails new` скелет собирается |
| 6 | campfire | harness preflight на чистом клоне |

Фазы 0–1 можно делать независимо от остального дерева; фаза 3
требует 1–2; фаза 6 требует всю часть A.

## Что сознательно НЕ входит

- Sprockets-модель (Sass/Transpile/конкатенация) — CRails выбрал
  propshaft-путь; при нужде транспиляции — внешний `vite`
  (`railties_cr/src/vite_dev.cr` уже проксирует dev, build —
  вне фреймворка, как jsbundling-rails).
- `importmap`-packager (`bin/importmap pin` с jsDelivr/npm) —
  отдельная P2-задача importmap_cr (нужен HTTP-клиент).
- CDN/`asset_host` — вне скоупа.
