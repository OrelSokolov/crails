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

## License

MIT
