# action_pack.cr — порт ActionPack (контроллеры, роутинг, params)

> ⚠️ EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.

Неймспейсы: `ActionController`, `ActionDispatch` — 1:1. Оценка: ~90%.

## Цель

Контроллеры и роутинг, ощущаемые как Rails: `before_action`,
`resources :posts`, `params.require(...).permit(...)`, `render json:`,
`redirect_to`, flash/session/cookies.

## API 1:1

### Контроллеры (P0)
- `class PostsController < ApplicationController` ( ApplicationController
  < `ActionController::Base`)
- `before_action :authenticate, only: [:index] / except:, if:, unless:`
  (+ `prepend_/skip_`) — макрос с `**opts`
- `render plain:/html:/json:/template:/partial:/layout:, status: (символ
  или число), formats:, locals:`, `render_to_string`, `head :no_content`
- `redirect_to path, notice:/alert:`, `redirect_back fallback_location:`,
  `redirect_back_or_to`
- `respond_to do |format| format.html { } format.json { } end`
  (фикс-методы вместо method_missing-коллектора)
- `rescue_from Exception, with:` (макрос)
- `request.headers/method/get?/post?/format/remote_ip/user_agent/
  original_url/query_parameters/body/authorization`; `response.headers/
  status/...`
- `send_data/send_file (filename:, type:, disposition:, range:)`

### Strong params (P0)
`params[:id]`, `params[:person][:name]`, `require(:post)` (raise
ParameterMissing → 400), `permit(:title, :body, tags: [], addresses:
[:id, :zip], preferences: {})`, `expect`, `to_h/to_unsafe_h/slice/except/
dig/fetch`. Ключи Symbol|String без разницы (аппроксимация
HashWithIndifferentAccess).

### Cookies / session / flash (P1)
`cookies[:k] = v` (`expires:, path:, domain:, secure:, httponly:,
same_site:`), `cookies.permanent/signed/encrypted`, `cookies.delete`;
`session[:user_id]`, `reset_session`; `flash[:notice]/flash.now/keep/
discard`, `add_flash_types :warning` (макрос).

### Роутинг (P0)
- `CRails.application.routes.draw do ... end` в `config/routes.cr`
- `root "welcome#index"`, `get/post/patch/put/delete path, to:`,
  `match via:`, `redirect`
- `resources :posts (only:, except:, shallow:, concerns:, param:, path:,
  as:, module:)`, `resource`, `member { } / collection { } / nested/
  shallow`, `namespace :admin`, `scope (path:, as:, module:, defaults:,
  constraints:)`, `constraints`, `defaults`, `concern/concerns`,
  wildcard `*path`, optional `foo(/bar)`
- Именованные хелперы `posts_path`, `edit_post_path(@post)`,
  `new_admin_post_url` — макрос-генерация (проверено зондом).
  Полиморфные массивы `url_for([:edit, @post])` — P2 (~70%).

### HTTP-кэш и стриминг (P2)
`fresh_when(etag:, last_modified:, public:)`, `stale?`, `expires_in`,
`http_cache_forever`; `ActionController::Live` на fiber'ах,
`response.stream.write/close`, `send_stream`.

## Реализация

- HTTP-слой: Crystal `HTTP::Server` + `HTTP::Handler`-цепочка = middleware
  стек с теми же операциями (`use/insert_before/insert_after/swap/delete`).
- Роутер: compile-time таблица + runtime матчинг сегментов;
  `*_path`-хелперы — макрос над `resources`/`get as:`.
- Конкурентность: fiber-per-connection (аналог threaded mode, но дешевле).
- `CRails.env` — enum с предикатами (`CRails.env.production?`).

## Фазы

- P0: маршруты (get/root/resources) + именованные хелперы, контроллеры
  (before_action, render/redirect, params require/permit), basic request.
- P1: cookies/session/flash (signed/encrypted), rescue_from, respond_to,
  send_data/file, middleware-стек API.
- P2: HTTP-кэширование, Live-стриминг, полиморфные урл-хелперы,
  `CRails.application.routes.draw` полный синтаксис.

## Готово, когда

scaffold-контроллер из Rails-туториала (`resources :posts` + CRUD +
notice-flash + strong params) компилируется после `rails→crails` замены
только ERB→ECR и `Rails`→`CRails`.

## Зависимости

active_support.cr, railties.cr (boot), action_view.cr (render).
