# CRails — Philosophy: contracts first

> The first and most important document of the project. Everything else
> in the README is detail. If a conflict arises between the ideology
> and any feature, ideology wins.

Current status: the code is being ported from Rails one-to-one, so that
refactoring can happen later. This document is effectively a roadmap
and a promise for the future, not a description of what is already
implemented.

## Clean rails: teach best patterns, not magic

CRails stands for **Clean Rails (without Rust)**: Crystal here is a tool,
and "cleanliness" is the product. The framework is designed so that
a newcomer learning on it picks up the best patterns the industry has
been running on for decades. Explicit concepts and abstractions are
easier to understand, easier to hand over to teams, and safer to evolve:
code written against an explicit interface doesn't need to be relearned
whenever approaches change.

So the priorities are: explicit contracts and interfaces > code
expressiveness > magic (dead last; wherever Rails relies on runtime
magic, we have compile-time macros — they at least can be read in the
sources). The benchmark of longevity is interfaces that serve for
decades: the Unix file, C-ABI, sockets. A socket has an interface, a
server-client pair has an interface, and everything just attaches to
them — nothing breaks off. CRails contracts must live the same way.

Internal standard for contract expressiveness: **a module-interface is
preferred over an abstract class** (a module with abstract methods,
`include` instead of inheriting from a framework class) — a contract
without implementation, verified by the compiler. Contracts can be
extended and supplemented (a new interface includes the old one), but
the names and semantics of old methods are untouchable: code written
against the old interface works exactly as intended. Need to do it
a new way — a new interface is created alongside, with new
implementations for it; the old one is never repurposed.

## Two reasons to choose clean rails

**Business** chooses them for an architecture whose contracts don't
break. That is direct money: having invested once, the business gets a
stable income for years. New things — say, a security feature — attach
to a living old interface with new code, and it works and starts up
without touching what is already written. Evolution happens
incrementally: budget goes to new functionality, not to rewriting what
already works.

**A newcomer** chooses them to learn not magic, but the best design
patterns right away. Having mastered the framework, they understand how
the principles that hold up the internet and many working businesses
operate — not fleeting solutions, but foundations forged over decades.
At the moment it may look unfashionable, not like the latest trend —
but it is an investment in the future incomparably better than pretty
magic for magic's sake: magic changed tomorrow and died, while these
principles persist precisely because business, having invested in them
once, gets a stable income.

## Contracts are business

Business does not exist without long-lived contracts — with customers,
partners, contractors. Code is no exception: a framework's API is a
contract with whoever has invested months of work and the company's
money into it. A framework that changes its own contract in a new
version shifts those costs onto the invested parties — and trust takes
a long time to recover afterward. So we treat API immutability as a
framework's direct duty, not a gesture of goodwill.

## Lessons from Ruby on Rails: why we take a different path

Let's start by acknowledging merit: Rails had everything it needed to
become the best framework for business in the world. Elegant, readable
code. A popular and intuitive database pattern (ActiveRecord). A clear
structure on which enormous applications can be built. But these
strengths are weakened by one systemic property: Rails has no explicit
contracts, and major versions regularly revisit what has already been
released. Let's examine what this teaches us.

- **Lesson 1: cost of ownership over distance is higher than
  advertised.** "Batteries included, nothing to do" — but major releases
  require migrations, transitions like RSpec 2→3 — manual rewriting of
  tests, and libraries have to be glued together by hand. This work
  creates no new value for the business, but costs money and time.
- **Lesson 2: orientation toward newcomers creates risk for those who
  invested.** The promise "write fast and extend fast" should work
  always, but a feature can disappear along with the maintainer's
  decision (example: TypeScript support was removed, then brought back —
  formally "nothing changed", in fact trust suffered). Companies that
  plan for years account for such risk when choosing a stack.
- **Lesson 3: stated ideology gets revised over time.** Methods are
  removed (`update_attributes`), defaults change (`belongs_to` became
  required), semantics change (`errors`). Each such migration is budget
  and downtime, and the company gets an ultimatum "rewrite part of your
  code — then you get new features." It's not about chasing modernity:
  an architecture in which evolution requires rewriting forces you to
  throw away working code. Business expects otherwise — what was bought
  once stays good, and new things are added alongside.
- **Lesson 4: implicit contracts and lots of magic.** Behavior that
  cannot be seen by reading a file; metaprogramming where it isn't
  needed; a new dependency — and something changes in runtime. For large
  companies such risks are hard to assess and insure.
- Ruby has no performance prospects (interpreter, GVL, memory), and the
  core was held up by a single person who stepped away from daily Rails
  development more than ten years ago.

Notably, PHP and Perl are alive to this day. Rails's difficulties are
not so much about Ruby as about the practice of regular rewrites: at
some point a business gets tired of updating code without value growth
and asks "maybe rewrite it in something else?" — and suddenly it turns
out that Ruby isn't the fastest, there are more interesting languages,
and "writing convenience" turned into expensive maintenance. Long-term
promises are not confirmed at such a distance. It is precisely this
experience that shaped our contract-immutability rules.

## Ruby as a language: the same story

Ruby had every chance to become a comfortable language for decades. In
practice, compatibility was regularly sacrificed to new features:

- **Syntax compatibility was broken regularly.** Python went through
  one break (2→3) and tried not to repeat it. Ruby changed more often:
  new language versions periodically carried incompatibilities. A
  classic — the separation of keyword arguments in Ruby 3.0: old code
  worked, and then it stopped. Weeks and budgets went into churning
  through files and hunting down errors — with no functional gain.
- **Alternative implementations did not survive.** Rubinius and other
  backends became impossible to maintain: the language changed faster
  than implementations could catch up. The ecosystem narrowed to a
  single implementation — a direct consequence of the pace of
  incompatible changes.
- **The circular dependency language↔framework↔gems.** A new Rails
  *requires* a new Ruby, gems in turn require their own Ruby version.
  You can't update one without the others: a company gets a bundle
  "language + framework + all gems at once" with the risk that the
  entire stack falls apart. This is expensive and contradicts the
  original promise of low entry cost.

## Why Crystal, and not Rust

The natural objection: "if you're already leaving Ruby, why Crystal and
not Rust?". The answer lies in the level. Rust is a systems-level
language, and not above it. A web developer is like a business-taxi
driver: their job is to watch the road, choose the route, monitor the
situation, ensure the client's comfort in the cabin. Rust is driving
the car not with a wheel and pedals, but with a device wired directly
into the engine: you can send very efficient signals to the motor, but
it has nothing to do with the main job.

> **The main take on agents and "efficiency".** A programming language
> is a model invented by humans for humans. Technically an agent can
> write LLVM IR, or straight machine code — and debug it; such code
> would be even more efficient than Rust. But almost nobody promotes
> that idea. One wonders: why, in the pursuit of efficiency, does
> everyone stop at Rust? The sobering answer: it's not about
> engineering, it's about hype. Generation efficiency is not the real
> criterion. The real criterion is what happens to the code later: how
> hard it is to maintain, how much the abstractions blur in it, how
> much the memory-model constraints get in the way of solving the task.

- **Business applications don't need its guarantees.** Constant
  borrow-checking, explicitly describing thousands of types and
  structures — a price paid for problems that simply don't exist at the
  application level. Most applications are built from a template: a
  systems programmer wrote and tested the template once, with explicit
  details — everyone else takes the ready-made thing. A web developer
  has no reason to write their own HTTP server for every application —
  and that's how the industry has lived for decades, including when
  "safe" Rust didn't exist yet.
- **A systems layer in Rust is fine.** A JS runtime at Bun's level —
  yes, no questions. But rewriting application-level Ruby-, Python- or
  JS-code in Rust is a dubious undertaking even at a tenfold speedup:
  such code is harder to read and maintain, and the benefit for most
  application-level software is small.
- **Sufficient speed instead of absolute speed.** Speed is not a
  feature when you already have enough. Languages slower than Crystal
  have lived in production for decades. If Crystal runs ~2× slower than
  Rust — that's a level with plenty of margin for virtually any web
  project.
- **Generation can be done in anything — a human will review it.** In
  the era of agents, code-generation speed stops being a language
  advantage: an agent will write Rust too. The difference shows at the
  next step — re-checking. For applications without risk, code may not
  need to be read at all. For applications with risk — finance,
  medicine, personal data — a human in the loop is always needed. And
  here generation speed in Rust runs into reading: a person who doesn't
  know Rust cannot check such code — and that's where the sandcastle
  collapses. Crystal reads almost like pseudocode: compact, without
  syntactic noise, business logic visible right away — and what was
  written can be understood quickly, even without an agent. Reviewing
  an agent's work, security audits, incident analysis — these are
  reading operations, and on Crystal they are cheap.
- **What Crystal gives with margin:** faster than Ruby and Python;
  C-ABI — any system extensions in C plug in directly; cheap fibers
  instead of manual thread work; Ruby-level syntax — readable, elegant,
  expressive, including for specs and tests (try writing as many tests
  in Rust, and as pleasantly). The language has already proven its
  level in production: **LavinMQ** — an AMQP broker written entirely in
  Crystal — beats RabbitMQ (Erlang/OTP) in throughput at lower memory
  consumption. Our own measurements of the same kind: 142k RPS
  hello-world, 2.7M msg/s over websockets, ~1M jobs/sec — that's more
  than enough for web projects for years ahead.

### The price of Rust's memory model

Speed without GC and with zero copying is bought with constraints on
the very shape of programs.
A classic acknowledged by the Rust community itself (see the meme-book
"Learning Rust With Entirely Too Many Linked Lists"): a doubly-linked
list — a node has two "owners", and ownership does not allow such a
construction; self-referential structures — require `Pin` and `unsafe`;
graphs and trees with a parent pointer — `Rc` cycles leak, there's no
cycle collector; holding `&mut` across `.await` — forbidden.
The workarounds are everywhere the same: `Rc<RefCell<T>>`,
`Arc<Mutex<T>>` or an arena with indices — that is, a manual simulation
of what a GC does for free.

And the main trick: `RefCell` checks borrows **at runtime — by
panicking**. A language sold as safe actually offers a choice of two:
either safety constrains the shape of the program so much that simple
things require "first figuring out how to even implement it", or errors
move from compile time into runtime — and you get runtime crashes as in
Ruby or Python, having paid the full price of Rust's complexity. And a
panic is not an exception: in Crystal an error is caught by an ordinary
`rescue` anywhere and handled as part of the logic; a Rust panic in the
main thread kills the entire process (exit 101), the only interception
is `catch_unwind`, a loophole with `UnwindSafe` mechanics, designed for
FFI and thread boundaries (the documentation honestly warns that it
doesn't catch all panics), and with `panic = "abort"` it isn't caught
at all. A fatal `borrow_mut()` on a `RefCell` — not "an exception you
can catch", but a program crash.

A real case: on November 18, 2025 Cloudflare suffered its worst outage
since 2019 due to a single panic in Rust code. A permission change in
ClickHouse duplicated lines in the Bot Management config file, the file
exceeded the feature limit — and the code of the new FL2 proxy called
`.unwrap()` on an `Err`: `thread fl2_worker_thread panicked`. Instead
of one function degrading, requests fell into 5xx across the whole
network: core traffic wasn't routed for almost three hours, Access,
Turnstile and Workers KV were down
([post-mortem](https://blog.cloudflare.com/18-november-2025-outage)).
One unhandled `Err` in a "safe" language — and a company through which
a noticeable part of the internet flows stands still for three hours.

As a follow-up — a comedy of the AI era: in agent instructions
(AGENTS.md, CLAUDE.md) for Rust projects people en masse write "do not
use `unwrap`". The C++ equivalent would read as "dear AI, do not leak
memory, do not leave dangling pointers and do not forget destructors".
Safety that has to be spelled out in a prompt is not a property of the
language but a discipline: exactly what C++ has been suffering from for
decades. And the claimed advantage remains partly illusory anyway:
memory leaks in Rust are legal and safe (`mem::forget`, `Rc` cycles —
that is not `unsafe`), so even on leaks, prompt discipline remains the
last line of defense. The language, of course, still protects from UB —
but from the marketing of "safe by default" it is separated by a
respectful distance.

Code loses readability from this,
maintenance gets more expensive, and the developer fights the memory
structure, forgetting about business requirements. And the best code is
the one that most accurately reflects the program's business
requirements. Crystal (GC and simple ownership) keeps the focus on the
domain, not on fighting the language.

CRails's goal is not to "beat Rust at everything", but to squeeze so
much benefit out of Crystal that you never have to think about anything
greater.

## Industry pays for immutability

A comparison with languages that don't break contracts — and their
market fate:

| Language | Policy | Result |
|---|---|---|
| **Java** | Binary and source compatibility since 1996: bytecode compiled 25 years ago runs on a modern JVM. Obsolete APIs (Vector, Hashtable) are not removed — they're left in place and new ones are added alongside. The only noticeable break — Java 9 (module system) — and it is exactly that one enterprise remembers as a disaster | Lives in enterprise solutions for decades. Enterprise is always good money |
| **Go** | "Go 1 compatibility promise" — a public document-promise since 2012, ~14 years without breaking changes | Corporate trust, the #1 language for infrastructure |
| **C/C++** | Standards without breaking contracts (C89→C23, C++ "don't break my code"); C-ABI stable for ~50 years (details below) | All cross-language bindings in the industry rest on C-ABI |
| **Rust** | Editions: new syntax — a new edition alongside, the old one compiles forever, `cargo fix` migrates automatically | The fastest-growing language, corporate darling |
| **Python** | Broke once (2→3) — the ecosystem split, migration took ~a decade | A lesson for the whole industry |
| **Ruby** | Compatibility was broken regularly (see above) | The enterprise segment shrank noticeably |

Conclusion: contract immutability is what enterprise trusts and pays for
decades. Broken trust recovers very slowly, and the market has a long
memory.

## Living fossils: 20–60 year old code in production and in profit

A study: where technologies written 20+ years ago still work, are not
updated — and yet keep companies afloat, generating profit for decades.

| Technology | Age | What it holds up today | Why it's alive |
|---|---|---|---|
| **COBOL** (1959) | 65+ years | An estimated ~220 billion lines of code; ~95% of ATM transactions and ~43% of US banking systems | The language never changed: code from the 1980s spins in the cores of banks and generates money right now |
| **IBM System/360 → z/OS** (1964) | 60 years | Mainframes — the settlement core of ~70% of Fortune 500 | Backward compatibility "down to the 60s built-in": a binary built half a century ago runs on a modern machine |
| **MUMPS** (1966) | 58 years | Epic Systems — medical records of 250+ million US patients | The contract of language and data never broke — hospitals don't rewrite what works |
| **Sabre** (1960s) | ~60 years | Airline booking (American Airlines and the market) | The system was rewritten around it, but the data contract lived |
| **SWIFT** (1973) | 50+ years | International bank payments, trillions of $ per day | A protocol contract |
| **SS7** (1980s) | ~40 years | All world telephony, including 4G/5G roaming | A protocol — a frozen contract between the planet's operators |
| **SMTP / DNS / BGP** (1983–89) | ~40 years | Mail, domains, routing — the entire internet | RFC contracts: new things are added, old ones don't break |
| **zlib** (1995) | ~30 years | Compression in every browser, server, phone | Stable C-ABI, running on billions of devices |
| **SQLite** (2000) | 25 years | The most widespread DB engine in the world | File format backward-compatible since 2004; 100% branch coverage as a contract |
| **Apache** (1995), **PostgreSQL** (1996) | ~30 years | Half of the old-school web, thousands of SaaS | Module/SQL contracts don't break |

Three conclusions from this table:

1. **This is not a disgrace, but the ideal.** Every line of COBOL in a
   bank is a contract that was honored. The bank invested once and gets
   profit for 40 years. That's what "code is an asset" means.
2. **Companies don't update — and that is rational.** Updating without
   breaking is an option people happily pay for. Breaking is a
   catastrophe: if banks/telephony/DNS stopped even for a day, the
   losses would be counted in billions. "If they broke, it would be
   very sad" — that's why the market chooses those who don't break.
3. **The secret of longevity is one: an immutable contract.** Language,
   ABI, protocol, file format, SQL — anything, as long as it's frozen.
   None of the "fossils" would have survived if COBOL from 1990 didn't
   compile in 2010.

That's exactly how we want CRails code to live: an application written
today must have the right not to be rewritten for 20 years — because
the framework's contract is frozen, not "to be revisited in the next
major".

## C and C++: how to evolve without breaking (and C-ABI as the industry's glue)

A separate case — the C/C++ family, because it proves both things at
once: evolution without major breaks, and a standard contract on which
other languages survive.

- **C has been standardized since 1989 (C89), standards come out every
  ~10 years (C99, C11, C17, C23) — and old code compiles.** A telling
  detail: when C99 needed new keywords, they were wrapped in reserved
  `_`-names (`_Bool`, `_Complex`) so as not to take identifiers away
  from existing code. That's the level of respect for a contract: the
  language changed — your code didn't notice.
- **C++ evolves by the rule "don't break my code"** — officially the
  committee's top criterion when accepting proposals into the standard.
  Billions of lines of C++98 are built by modern compilers; even the
  removal of long-obsolete APIs (`auto_ptr`, trigraphs) stretched over a
  multi-standard cycle with years of warnings. Meanwhile the language
  gained templates, lambdas, concepts, modules — growth without
  revolutions.
- **C-ABI is the most successful cross-language contract in history.**
  ~50 years of an unchanging binary calling convention — and it is on
  it that ALL bindings between languages rest: Python/Ruby/Node
  extensions, Rust/Go/Crystal bindings, JNI and P/Invoke, OS system
  calls, shared libraries, plugins. No language "does FFI" with another
  language — everyone does FFI with C-ABI.
- The key point: **this standard is not revisited every 5 years — it
  was made once, and everyone adapts to it.** The Python+C binding,
  Crystal+libvips, Node+N-API are possible precisely because the C
  contract didn't flinch for half a century. Change it — and all bridges
  between all languages of the world would fall off at once.

An honest caveat: C++ itself has no stable ABI across compilers (and
that is its known pain) — which is why the industry chose C-ABI as the
cross-language contract. This once again confirms the rule: it's not
the prettiest interface that wins, but the most immutable one.

C-ABI is the second example after the Unix file of an eternal contract
from our promise No. 6: fix it once — and the whole world adapts to you.

## The economics of breaking contracts

Let's record separately the economics of contract-breaking. When a
company migrates because the framework broke itself, its money is not
invested anywhere:

- it does **not go to developing the language** and ecosystem;
- it does **not go to developing the skills** of developers (rewriting
  `update_attributes` → `update` teaches nothing new);
- it does **not create features** for the company's customers — prod
  doesn't move.

This is work without new value: weeks of effort go only into restoring
what already worked. All else being equal, a rational company will
choose the option without such costs.

## The AI era: explicit contracts are mandatory

AI tools make the problem not softer, but harsher. When code is
generated, people less and less often check every line by hand — and
without explicit contracts this creates an even greater risk that
something falls off right in production.

Stack reliability is a product, not a sum:

```
R = C × T × K
    C — compiler (static checks at the gate)
    T — tests (behavioral contract)
    K — framework contracts (API immutability)
```

A product — because zero in any factor zeroes everything:

| Stack | C | T | K | R |
|---|---|---|---|---|
| Java/Spring | yes | yes | yes | high |
| Go, Rust | yes | yes | yes | high |
| CRails | yes | yes | yes | high (the goal) |
| Ruby on Rails | **no** (interpreter) | yes | **no** | close to zero |

Multiply language reliability by framework reliability — and the
numbers come out not "a bit worse", but orders of magnitude worse. In
the AI era the winners are stacks with maximally explicit contracts,
recorded in code and machine-enforced. Generated code needs checkable
bounds, not magic.

There is also an economic side: reading code becomes a scarce resource.
Developers already spend less time on it — and will spend even less.
Explicit contracts and explicit interfaces allow the human eye to
verify as quickly as possible what is actually written in the project:
you look at the code — you see the interface, you see how the system
works — and that's it. Neither agent tokens are spent on reading
everything in sight, nor human time, nor useless tests run to figure
out what an explicit interface would show right away. This is direct
savings: fast time-to-market and low maintenance cost — and low
maintenance cost is achieved precisely by explicit contracts. Plus
convenient extensibility: new things attach to a living old interface,
not instead of it.

And conversely: the fact that in the AI era one can generate hundreds
and thousands of lines of code effortlessly does not mean one should.
Rewriting the same functionality twenty times won't make your customers
happier — happiness is made by what works and is cheap to maintain.

Separately about responsibility. However good AI may be, companies sign
contracts not with agents but with other companies, where people work —
and people are responsible for the finished result. Until a shift
happens where contracts are signed directly with AI and AI bears
responsibility for the outcome, a human stays in the loop: someone must
check, understand, and sign off on what the agent did. Which means this
approach stays in demand too — code that a human can quickly read and
check, and contracts that don't shift under their feet.

And lastly: reputation is built from kept promises. A stack with a
history of brittle updates loses the comparison before it even begins —
which is why CRails intends to earn trust with honored contracts.

## CRails's promises (the framework's contract with you)

1. **Contracts are eternal.** A contract, frozen at the moment of
   release, works forever. No "rewrite to the new API" — never.
2. **Security is fixed in all living versions.** A hole is closed in
   your contract, not "in the next major — please upgrade".
3. **New features are new contracts alongside.** Decided to do
   websockets or jobs the new way? We add `cable_v2`, `jobs_v2`. The
   old contract keeps working unchanged.
4. **Migration is for the goodies, not under threat.** Versioning is
   declared per contract separately. Upgrade what you want, when you
   want. You may upgrade nothing — forever.
5. **Batteries included** — as in Rails. The only difference: new
   batteries don't break the old ones.
6. **The benchmark is the Unix file.** The file-descriptor interface has
   worked for forty-plus years with any device. Our contracts must live
   the same: for decades, not "a year or two — and a new budget for
   upgrades".
7. **Your code is an asset.** We do not put a company before the choice
   "delete half your code for modern features". We treat with respect
   any person and any business that chose this framework.
8. **Explicitness over magic.** Metaprogramming — only under the
   framework's hood, hidden inside it itself. Everything the user
   touches is maximally explicit: readable by viewing a file, checkable
   by a test — and unchanged after release. The code won't suffer much
   from this, but maintenance will become substantially better.
9. **No circular dependencies.** Updating one contract never requires
   simultaneously updating the language, toolchain, or other contracts.
   The update radius is exactly the one you chose yourself.
10. **Components don't depend on each other.** If action_mailer,
    action_pack, action_text, action_view, active_job, active_record
    are tightly coupled — those are not separate components, but one.
    The proper split: each component updates separately, and one can
    assemble a mix-and-match constructor from different versions of
    libraries ("a salad") — this is normal behavior in all other
    technologies. Updating the jobs library doesn't drag along the mail
    library. We don't fight for pretty headlines "we updated absolutely
    everything".

## What backs the promise (mechanics, not an honest word)

- A contract = a named, versioned API surface + a frozen corpus of
  oracle specs (tests 1:1 with the originals, see AGENTS.md).
- CI rule: every release passes the specs of all contract versions ever
  released. Broke an old contract — the release doesn't ship.
- Evolution is additive only: adding a method is allowed, removing one
  or flipping a default is not. A new path = a new contract version
  (`V2` alongside `V1`); in a compiled language the second facade costs
  zero runtime — only what the application uses gets into the binary.
- Deprecation is a compile-time label pointing to the new path, not
  removal.
- Components (shards) are versioned independently. Interaction between
  them — only through frozen contracts (for example, mailer enqueues
  jobs through the active_job contract, rather than poking into its
  internals) and always optional: no dependency — the component works
  alone. CI assembles the "salad": a matrix of different released
  versions of components, so that combinations never break.

## The path for Rails applications

We do not abandon the Rails way: the ActiveRecord pattern, job
contracts, convention over configuration — all of this stays. The 1:1
API (the only namespace difference — `CRails`) is needed so that a
Rails application ports over nearly verbatim. But further — movement
toward a cleaner architecture: contracts are thought through before
release and not broken after. We are starting this path anew, from the
framework's first versions.

## Comparison

| | Ruby on Rails | CRails |
|---|---|---|
| API contract | not formalized, revisited in majors | frozen at release, eternal |
| New features | often require migrating the whole framework | new contract alongside, old one untouched |
| Upgrading | atomic: everything at once | per contract, optional |
| Language↔framework dependency | circular: new Rails requires new Ruby, gems — their own minimum | updating a contract drags nothing along |
| Components | coupled: a major updates everything at once, you can't take one | independent: a salad of any released versions |
| Breaking change | justified by a changelog | impossible: the CI matrix won't ship the release |
| Staying on the old | pain (gems, security, EOL) | a valid path forever |
| Performance | Ruby's ceiling (interpreter, GVL, memory) | Crystal: fibers, one binary — see the benchmark in README.md |
