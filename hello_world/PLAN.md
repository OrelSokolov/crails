# hello_world — Iteration 0: Hello World на CRails ✅ (2026-10-02)

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

**Статус: сделано.** Приложение `hello/` сгенерировано `crails new`,
`crails server`/`routes`/`watch` работают, curl → 200, цифры сняты в
`../bench/results/000-hello.md`.

Первая итерация всего проекта. Цель: минимальное CRails-приложение
от `crails new` до HTTP-ответа, плюс первый замер против Rails 8 + Puma.

## Что должно работать

```sh
crails new hello        # каркас приложения
cd hello
crails server           # сборка + запуск (по умолчанию :3000)
curl localhost:3000/    # -> 200, HTML-страница "Hello from CRails"
crails routes           # -> root welcome#index
crails watch            # rebuild при изменениях (dev-цикл)
```

## Состав приложения

```
hello/
  shard.yml             # deps: railties, action_pack, action_view, active_support
  config/application.cr # class Application < CRails::Application
  config/routes.cr      # CRails.application.routes.draw { root "welcome#index" }
  config/environments/{development,production}.cr
  app/controllers/welcome_controller.cr
  app/views/welcome/index.html.ecr     # layouts/application.html.ecr
  app/views/layouts/application.html.ecr
  bin/crails
  public/
```

Задействованные минимальные слои (вычитаются из планов P0 шардов):

- railties.cr P0: `crails new/server/routes/watch`, boot, env
- action_pack.cr P0: root-маршрут, контроллер, `render` (шаблон+layout),
  `CRails.env`, логгер
- action_view.cr P0: ECR-рендер, layout + yield
- active_support.cr P0: только то, что тянут остальные (логгер, to_fs)

Без БД, без сессий, без формы — минимальный срез.

## Метрики Iteration 0 (bench/)

На одной машине, тот же `/` (статическая HTML-страница из шаблона):

- RPS и p50/p99 (wrk/k6, warmup, 3 прогона): CRails vs Rails 8 + Puma
- RSS памяти
- время старта (без учёта компиляции) и размер бинарника
- время компиляции (отдельно — это цена dev-цикла, честно фиксируем)

Критерий успеха итерации: цифры сняты и записаны в `bench/results/000-hello.md`,
приложение живо, roadmap скорректирован по фактам.

## Не делаем

Всё, что не нужно для `curl /` → 200. Никаких конфигов «на будущее».
