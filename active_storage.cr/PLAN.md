# active_storage.cr — порт ActiveStorage

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейс: `ActiveStorage` — 1:1. Оценка: ~85% (DSL — макрос 1:1;
стоимость — обработка картинок vips/ffmpeg, не разрыв API).

## API 1:1

### DSL
- `has_one_attached :avatar (dependent: :purge_later, service:,
  strict_loading:, analyze:)` — макрос; генерит `avatar`, `avatar=`,
  `avatar_attachment`, `avatar_blob`, scope `with_attached_avatar`
- `has_many_attached :photos` (+ блок именованных вариантов:
  `attachable.variant :thumb, resize_to_limit: [100, 100]`)

### Attachable-прокси
- `avatar.attach(io:, filename:, content_type:)` / `attach(signed_id)`
  / `attach(Blob)` / `attach(UploadedFile)` (union-типизация)
- `avatar.attached?`, `detach`, `purge`, `purge_later`
- `avatar.variant(resize_to_limit:/resize_to_fill:/resize_and_pad:/
  crop:/rotate:/format:)` → `#url`, `#processed`, `#download`
- `avatar.preview(...)`, `representation(...)`
- `avatar.url (expires_in:, disposition:, filename:)` — direct URLs
- `avatar.download { |chunk| }`, `open { |tmpfile| }`
- Blob: `byte_size, content_type, filename (basename/extension/
  sanitized), checksum, metadata, key, signed_id, image?/video?/
  audio?, custom_metadata, analyzed?`
- `ActiveStorage::Blob.find_signed!`

### Сервисы и конфиг
- `config/storage.yml`: `Disk (root:)`, `S3`, `Mirror`; выбор средой:
  `config.active_storage.service = :local`
- Маршруты `/rails/active_storage/blobs/{redirect,proxy}/...`,
  `/rails/active_storage/representations/...`,
  `POST /rails/active_storage/direct_uploads` (presigned PUT для S3)
- Фоновые джобы: AnalyzeJob, PurgeJob (active_job.cr)

## Реализация

- Variants: libvips-биндинг (кандидат) или шелл-аут `vips`; превью
  PDF/видео — ffmpeg/poppler шелл-аут (как у Rails); ленивая обработка
  + кеш по variation key.
- S3-сервис: presigned URL через sigv4 (OpenSSL stdlib) — без SDK.
- `ActiveStorage::Current.url_options` — fiber-local.
- Утиная типизация attachable (7 форм в Rails) → перегрузки/union.

## Статус (Iteration 5 — P0 готов)

- Oracle: `oracle/cases.rb` → `oracle/expected.yml`, 27 кейсов сняты с
  activestorage 8.1.4 (SQLite in-memory, Disk-сервис; blob create/find/
  checksum/content-type-предикаты/filename sanitize, attach/detach/purge,
  has_one_attached). Зеркало: `spec/oracle_spec.cr` — 29/29 (27 оракул +
  mirrors-check + юнит purge).
- Реализовано: `filename.cr` (sanitized: пробелы сохраняются, `/`\`\\`
  → `--`), `service.cr` (DiskService upload/download/exist?/delete +
  Checksum md5_base64 через OpenSSL), `blob.cr` (AR-модель с
  `set_table_name`, `create_and_upload!`, key — 24 символа [A-Za-z0-9],
  image?/video?/audio? и пр., purge), `attached.cr` (Attached::One:
  attach/attached?/blob/download/filename/detach/purge + макрос
  `has_one_attached` через reopen `ActiveRecord::Base`).
- Отклонения от Rails (сознательные, P1+): signed_id — Rails-специфика
  (HMAC-схема) — своя реализация P1; сервис-реестр для P0 — один
  именованный Disk-сервис (`Blob.services`); S3/Mirror/variants/preview/
  direct upload — P1+. Фикстурные таблицы blobs/attachments несут
  `updated_at` (AR-порт пишет оба timestamp при insert безусловно; у
  Rails storage-таблиц их нет).
- Спеки шарда запускаются `crystal spec` из корня шарда — кодеген AR
  подхватывает `db/schema.yml`.

## Фазы

- P0: Disk-сервис, has_one_attached/has_many_attached, attach/attached?/
  download/url, blobs/attachments-таблицы, AnalyzeJob.
- P1: variants (vips), preview (ffmpeg/poppler), purge_later, direct
  upload (S3 sigv4), Mirror.
- P2: именованные варианты-блоки, custom_metadata полный, proxy-режим.

## Готово, когда

`user.avatar.attach(io:, filename:)` + `user.avatar.variant(resize_to_limit:
[100,100]).url` отдают работающий URL ресайзнутой картинки с диска.

## Зависимости

active_record.cr, active_job.cr, libvips (P1), ffmpeg/poppler (P1).
