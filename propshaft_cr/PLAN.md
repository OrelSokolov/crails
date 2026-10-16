# propshaft_cr — план/статус порта propshaft 1.3.2

Порт компилятора asset pipeline для CRails. Эталон — гем propshaft
1.3.2 (та же версия, на которую опирается `railties_cr/src/static.cr`).

## Что сделано

- **oracle** (`oracle/`): фикстура + 44 кейса на настоящем геме
  (`propshaft_cases.rb` → `propshaft_expected.yml`); зеркало —
  `spec/propshaft_spec.cr` (байт-в-байт manifest/digest/контент).
- **реверс-проверка**: `oracle/verify_propshaft.rb` — гем пересобирает
  фикстуру и сверяет выход порта побайтово. Спек-обёртка —
  `spec/reverse_oracle_spec.cr` (skip без ruby в PATH; ручной gate:
  `spec/reverse_runner.cr` + verify на машине с ruby).
- **ядро** (`src/`): Asset / LoadPath / Compilers (CssAssetUrls,
  JsAssetUrls, SourceMappingUrls) / Manifest / OutputPath / Processor
  / Assembly / Resolver (Static/Dynamic) / Config.
- **railties**: `config.assets.*`, `CRails.application.assets`,
  `CRails::PropshaftHelper` (compute_asset_path во вьюхах),
  CLI `crails assets:precompile|clean|clobber|reveal`
  (`railties_cr/src/assets_tasks.cr`).

## Зафиксированные оракулом wire-детали (расходятся с интуицией)

- digest = SHA1(**сырой** контент + контенты referenced-ассетов +
  version), первые 8 hex — НЕ digest скомпилированного контента;
- манифест — `{"<logical>":{"digested_path":"...","integrity":null}}`
  (compact JSON, порядок вставки = readdir, без \n в конце). Простой
  формат (значение-строка) поддержан при чтении;
- файл **без расширения** не получает digest вовсе (`noext` → `noext`);
- JS-резолвинг — `RAILS_ASSET_URL("...")`, НЕ
  `new URL(..., import.meta.url)`;
- `url('../x.png')` из css в корне load path не резолвится (уходит за
  корень), `deep/../x.png` — чистится лексически;
- `OutputPath#clean`: reject-условие гема сравнивает String с
  ManifestEntry и никогда не срабатывает — текущая версия защищается
  свежестью mtime/позицией, а не исключением из списка. Портировано
  1:1;
- `fresh?` в ruby возвращает truthy (Fixnum/nil) — порт отдаёт Bool.

## Отклонения от гема

- **`.gz`/`.br` прекомпрессия** (`Config#versions`, CLI precompile) —
  CRails-расширение: соседи digest-файлов, отдаёт static.cr по
  Accept-Encoding. `.gz` — stdlib, `.br` — чистый Crystal (шард
  `brotli`, `Brotli.encode` quality 11). Гем ничего подобного не пишет.
- **`rails asset:precompile` грузит окружение приложения** — CLI
  `crails assets:*` в приложении (src/app.cr + config/application.cr)
  собирает `bin/app` и выполняет таску в окружении приложения:
  кастомный `config.assets.paths` виден (`Application#cmd_assets` →
  `CRails::AssetsCommands`). Bare-FS режим (исходников приложения
  нет, напр. Docker-стадия): load path — файловая система
  (app/assets/* + vendor/assets/* + vendor/javascript) и env
  `CRAILS_ASSETS_PATHS`; env работает в обоих режимах.
- **content_type-таблица минимальна** (css/js); всё прочее —
  pass-through копия. Отдачу делает static.cr со своей MIME-таблицей.
- **Regex на бинарном контенте** — закрыто: `Asset#scannable_content`
  (invalid UTF-8 байты выбрасываются, ASCII-паттерны матчатся как в
  ruby ASCII-8BIT); url в бинарнике резолвится (spec
  `binary_scan_spec.cr`).
- **parallel процессинга нет** — однопоточно (объём мал).
- **file_watcher/cache_sweeper нет** — dev-ревалидация через
  static.cr (mtime-кэш), не через LoadPath-кэш.
- **SRI**: `Asset#integrity` (sha256/384/512, base64) — есть,
  включается `config.assets.integrity_hash_algorithm`;
  `asset_integrity` хелпер — в `CRails::PropshaftHelper`.

## P2 (не сделано)

- `stylesheet_link_tag :all / :app` (asset_paths_by_type/by_glob);
- importmap-rails integrity-поля в JSON карты (`importmap_cr/PLAN.md`);
- cdn/asset_host — вне скоупа.
