# CRails — Clean Rails - The most beautiful compiled web framework

<p align="center">
  <img src="assets/icon.svg" width="200" alt="CRails — Clean Rails" />
</p>

> ⚠️ **EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.**
> This is an experiment. We are measuring performance and seeing what
> we get at this point. No compatibility guarantees whatsoever.

## Current status: a port of Ruby on Rails

At this point CRails is simply a **port of Ruby on Rails to Crystal**.
We are porting the framework in its current form: the framework itself,
its spirit and the beauty of its code. The code is being ported from
Rails one-to-one, so that refactoring can happen later — this is a
draft, not even a first release.

## Philosophy

The project's philosophy — explicit contracts first, lessons from
Rails and Ruby, why Crystal and not Rust, and the promises the
framework intends to keep — lives in **[IDEA.md](IDEA.md)**. It is
effectively a roadmap and a promise for the future, not a description
of what is already implemented.

## What this is

A full clone of the Ruby on Rails API on Crystal, as 1:1 as possible in
the end interface — so that a developer moving from Ruby/Rails feels no
difference. Goal: Rails application code ports to Crystal nearly
verbatim.

**The only namespace difference: `CRails` instead of `Rails`.**

- `CRails.application`, `CRails.env`, `CRails.root`, `CRails.logger` —
  as `Rails.*` was in Rails.
- `ActiveRecord::Base`, `ActiveSupport::Concern`, `ActionController::Base`,
  `ActionView::FormBuilder`, `ActionCable::Channel::Base`, `ActiveJob::Base`,
  `ActiveStorage::Blob`, `ActionMailer::Base`, `ActionText`,
  `ActionMailbox` — module names and API 1:1.
- ERB → ECR (the only visible substitution — the language is different).
- Commands: `crails` instead of `rails` (`crails new`, `crails server`,
  `crails generate`, `crails console`, `crails routes`,
  `crails db:migrate`).

## Why

An experiment to measure a **monolithic Rails MVC architecture on
Crystal**:

- how many users (RPS, concurrent connections) the monolith will
  withstand;
- how many jobs per second it will run (an ActiveJob-compatible worker);
- how many websockets it can hold (an ActionCable-compatible server);
- how much memory it eats in the process, how fast it starts.

Maybe it's "the new king of startups", maybe it's "a complete failure" —
we'll find out with numbers, not emotions. Benchmarks: `bench/`.

An API portability study (against real Rails 8.2 code): ~85–90% of
daily-use API ports with a 1:1 feel — full report:
`/home/oleg/egui.cr/plans/crails-api-research.md`.

### Performance: basic Hello page (no DB), head-to-head

Two minimal applications — route `/` → controller → `render plain: "Hello"`,
no database, no templates, no ORM. Both in production mode, one machine,
`wrk -t4 -c100 -d15s` after warm-up. CRails — `crystal build --release`
(a 5.4 MB native binary, full middleware stack: request-id, secure
headers, logging). Rails 8.1.4 — default Puma 8.0.2 (1 process × 3
threads), Ruby 3.4.5. Reproduction: `~/crails_compare/bench.sh`, full
report: `~/crails_compare/RESULTS.md`.

| Metric | CRails 0.1.0 (Crystal 1.21) | Rails 8.1.4 (Ruby 3.4.5) |
|---|---|---|
| **RPS** | **~50,000–52,000** | **~390–470** |
| Latency (avg) | ~2 ms | 211–256 ms |
| RSS idle | 11 MB | 99–100 MB |
| RSS under load (peak) | 17 MB | 101–102 MB |
| Socket errors / non-2xx | 0 | 0 |

A **100×+ boost in RPS** at **6–9× less memory** (two independent runs,
reproducible). Rails hits the wall of Puma's default 3 threads: 200+ ms
latency is the connection queue. More workers/threads will raise RPS,
but at the cost of a multiple in RAM (~100 MB per process vs. 11–17 MB
for the entire CRails application).

## Shards

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
- [railties.cr](https://github.com/OrelSokolov/railties.cr) — the `crails` CLI, generators, app glue (lives in this repo at `railties.cr/`)
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

## License

MIT
