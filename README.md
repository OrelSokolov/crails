# CRails — Clean Rails - The most beautiful compiled web framework

<p align="center">
  <img src="assets/icon.svg" width="200" alt="CRails — Clean Rails" />
</p>

> **Current status: a port of Ruby on Rails.**
> At this point CRails is simply a port of Ruby on Rails to Crystal.
> We are porting the framework in its current form: the framework
> itself, its spirit and the beauty of its code. The code is being
> ported from Rails one-to-one, so that refactoring can happen later —
> this is a draft, not even a first release.

## Philosophy

The project's philosophy — explicit contracts first, lessons from
Rails and Ruby, why Crystal and not Rust, and the promises the
framework intends to keep — lives in **[IDEA.md](IDEA.md)**. It is
effectively a roadmap and a promise for the future, not a description
of what is already implemented.

## Desktop and mobile now! ![NEW](https://img.shields.io/badge/NEW!-full_fullstack-2ea44f?style=for-the-badge&labelColor=0f0f0f)

CRails doesn't end at the server. With
[positron.cr](https://github.com/OrelSokolov/positron.cr) the same stack
ships **desktop and mobile** applications — go desktop, go mobile:

- the backend is a regular CRails application;
- the frontend is still plain HTML + CSS;
- all data work — models, queries, validations — lives on ActiveRecord
  (`active_record.cr`), embedded right into the client.

Compilation to a single native binary is what makes this possible:
the whole app — views, models and the database layer — ships as one
executable that runs as a native desktop application — a whole new
world for desktop apps.

## Installation

Install with [carat](https://github.com/crystal-carat/carat) package manager to get the binary:

```sh
carat install OrelSokolov/crails
```

## The best performance in class

Median RPS, official
[once-campfire-verification](https://github.com/basecamp/once-campfire-verification)
harness, AMD Ryzen 9 3900X stand:

| Route | Rails | Express | Go | Rust | C | Elixir | CRails |
|---|---|---|---|---|---|---|---|
| room_show | 1 731 | 10 430 | 14 316 | 21 953 | 31 698 | 2 346 | **38 092** |
| messages_page | 1 641 | 16 248 | 14 336 | 21 539 | 32 114 | 2 480 | **37 553** |
| sidebar | 1 804 | 19 979 | 14 945 | 24 411 | 34 857 | 2 566 | **52 299** |
| search | 1 801 | 17 764 | 15 988 | 25 113 | 33 460 | 2 522 | **48 930** |
| avatar | 28 046 | 40 989 | 48 656 | 74 442 | 18 920 | 31 896 | **76 669** |
| static_css | 37 048 | 42 843 | 59 413 | 72 389 | 37 095 | 36 788 | **75 962** |
| /up | 2 571 | 20 531 | 29 238 | 36 557 | 62 890 | 4 230 | **82 265** |
| post_message | 166 | 1 015 | 2 442 | 2 935 | 1 303 | 556 | 2 033 |

Beats Rust in some cases, but with beautiful code and the MVC pattern —
see more at the
[original repository](https://github.com/OrelSokolov/once-campfire-crails).

## Ecosystem

CRails is assembled from standalone shards, each living in its own repo
under [github.com/OrelSokolov](https://github.com/OrelSokolov?tab=repositories):

Base (resolved by the root `shard.yml`):

- [active_support.cr](https://github.com/OrelSokolov/active_support.cr) — core utilities, Concern, inflections
- [attr_reader.cr](https://github.com/OrelSokolov/attr_reader.cr) — Ruby-style `attr_reader` macros
- [erb.cr](https://github.com/OrelSokolov/erb.cr) — ERB templating (ECR)
- [action_view.cr](https://github.com/OrelSokolov/action_view.cr) — views, helpers, FormBuilder
- [action_pack.cr](https://github.com/OrelSokolov/action_pack.cr) — controllers, routing, middleware
- [importmap.cr](https://github.com/OrelSokolov/importmap.cr) — importmap-based JS assets
- [propshaft.cr](https://github.com/OrelSokolov/propshaft.cr) — asset pipeline (+ [brotli.cr](https://github.com/OrelSokolov/brotli.cr) precompression)
- [active_record.cr](https://github.com/OrelSokolov/active_record.cr) — ORM, migrations, adapters (db/pg/sqlite3)
- [railties.cr](https://github.com/OrelSokolov/railties.cr) — the `crails` CLI, generators, app glue
- [icr.cr](https://github.com/OrelSokolov/icr.cr) — `crails console`
- [project_watch.cr](https://github.com/OrelSokolov/project_watch.cr) — `crails watch`

Optional layers (add to your app's `shard.yml` when needed):

- [active_job.cr](https://github.com/OrelSokolov/active_job.cr) — background jobs
- [action_cable.cr](https://github.com/OrelSokolov/action_cable.cr) — WebSockets
- [action_mailer.cr](https://github.com/OrelSokolov/action_mailer.cr) — email
- [action_mailbox.cr](https://github.com/OrelSokolov/action_mailbox.cr) — inbound email
- [active_storage.cr](https://github.com/OrelSokolov/active_storage.cr) — file uploads
- [action_text.cr](https://github.com/OrelSokolov/action_text.cr) — rich text
- [action_bot.cr](https://github.com/OrelSokolov/action_bot.cr) — bots (webhooks + SSE)
- [devise.cr](https://github.com/OrelSokolov/devise.cr) — authentication
- [turbo.cr](https://github.com/OrelSokolov/turbo.cr) — Hotwire Turbo
- [live_view.cr](https://github.com/OrelSokolov/live_view.cr) — LiveView-style reactive views
- [kiq.cr](https://github.com/OrelSokolov/kiq.cr) — Sidekiq-compatible jobs backend
- [active_backup.cr](https://github.com/OrelSokolov/active_backup.cr) — database backups
- [action_mcp.cr](https://github.com/OrelSokolov/action_mcp.cr) + [active_agent.cr](https://github.com/OrelSokolov/active_agent.cr) — MCP servers and AI agents
- [serverx.cr](https://github.com/OrelSokolov/serverx.cr) — nginx-model zero-alloc HTTP server (buffer per connection, offset parser, master/workers via SO_REUSEPORT), compatible with any `HTTP::Handler`

## License

MIT

## What this is

A full clone of the Ruby on Rails API on Crystal, as 1:1 as possible in
the end interface — so that a developer moving from Ruby/Rails feels no
difference. Goal: Rails application code ports to Crystal nearly
verbatim.

The practical differences from Ruby on Rails — the `CRails` namespace,
ERB → ECR, the `crails` command, nilable finders, keyword arguments,
type narrowing and other consequences of Crystal's static typing —
are collected in **[DIFFERENCES.md](DIFFERENCES.md)**.
