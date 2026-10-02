# bench — замеры монолита CRails

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Смысл всего эксперимента: цифры. «Новый король стартапов» или «полный
провал» — решают они. Результаты складываем в `bench/results/`.

## Принципы честности

- Одна машина, один PG (то же ядро/настройки), тот же клиентский тул.
- Warmup перед замером; 3+ прогона, медиана.
- Сравнение всегда парное: CRails vs Rails 8.x + Puma (+ Sidekiq для
  джобов, ActionCable для ws) — идентичная логика приложения.
- Отдельно фиксируем compile time и время старта — цена dev-цикла.

## Сценарии

### 000-hello (Iteration 0)
`GET /` из шаблона. wrk: RPS, p50/p99, RSS, старт, бинарник.

### 100-ar-read (Iteration 2) — done, `results/100-ar-read.md`
`GET /posts/:id` — модель из PostgreSQL, пул коннектов.
Матрица fibers: 16/64/256/1024. Цель: найти потолок RPS и деградацию
латентности. + сравнение с Rails+Puma (threads 5/16).

### 101-ar-crud (Iteration 2) — done, `results/101-ar-crud.md`
`POST /posts` с валидацией → INSERT; транзакции.
Метрика: RPS записи, ошибки, лаг реплики нечестно — фиксируем только
локальный PG.

### 200-jobs (Iteration 4)
Минимум 3 конфигурации:
- async-адаптер (in-process fiber-пул) — CRails монолит
- PG-очередь (skip locked) — CRails durable
- Sidekiq + Rails (Redis) — референс
Метрики: джобов/сек, latency enqueue→perform при насыщении, потеря при
kill -9 (durability), RSS на воркер.

### 300-websockets (Iteration 4)
ActionCable-совместимый канал, broadcast каждые N мс.
Метрики: удержанные коннекты (цель 100k на одном процессе — проверяем),
сообщений/сек broadcast, память на коннект. Клиент: собственный
load-генератор на Crystal (fiber-клиенты) — wrk не умеет ws.
Референс: Rails ActionCable + anycable.

### 400-monolith-full (Iteration 6)
Богатое приложение: devise-аутентификация, CRUD, форма, джобы, ws.
Метрика «сколько пользователей выдержит монолит»: профиль смешанной
нагрузки (80/15/5 read/write/ws), время до деградации p99 > 500ms,
ошибки, RSS.

## Отчёты

`results/NNN-<name>.md`: окружение (CPU/RAM/ядро/версии), таблицы,
графики по желанию, вывод одной строкой (например: «CRails держит X RPS
при Y MB против Rails Z RPS при W MB»). Без маркетинга.

## Утилиты

- `bench/loadgen/` — Crystal-генератор (HTTP + ws + jobs), сам часть
  эксперимента.
