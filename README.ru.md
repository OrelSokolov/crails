# CRails — Clean Rails - The most beautiful compiled web framework

<p align="center">
  <img src="assets/icon.svg" width="200" alt="CRails — Clean Rails" />
</p>

> ⚠️ **EXPERIMENTAL FRAMEWORK, DO NOT USE IN PRODUCTION YET.**
> Это эксперимент. Мы замеряем производительность и смотрим, что
> получится на данный момент. Никаких гарантий совместимости.

## Текущий статус: порт Ruby on Rails

На данный момент CRails — это просто **порт Ruby on Rails на Crystal**.
Мы стараемся перенести фреймворк в текущем виде: сам фреймворк,
его дух и красоту кода. Код портируется с Rails один к один, чтобы
позже можно было сделать рефакторинг. Это черновик (draft) — даже ещё
не первый релиз.

## Философия

Философия проекта — явные контракты прежде всего, уроки Rails и Ruby,
почему Crystal, а не Rust, и обещания, которые фреймворк собирается
держать, — живёт в **[IDEA.md](IDEA.md)**. Это фактически дорожная
карта и обещание на будущее, а не описание того, что уже реализовано.

## Что это

Полный клон API Ruby on Rails на Crystal, максимально 1:1 по конечному
интерфейсу — чтобы разработчик, перешедший с Ruby/Rails, не почувствовал
разницы. Цель: код Rails-приложения переносится на Crystal почти дословно.

**Единственное отличие неймспейса: `CRails` вместо `Rails`.**

- `CRails.application`, `CRails.env`, `CRails.root`, `CRails.logger` — так,
  как в Rails было `Rails.*`.
- `ActiveRecord::Base`, `ActiveSupport::Concern`, `ActionController::Base`,
  `ActionView::FormBuilder`, `ActionCable::Channel::Base`, `ActiveJob::Base`,
  `ActiveStorage::Blob`, `ActionMailer::Base`, `ActionText`, `ActionMailbox` —
  имена модулей и API 1:1.
- ERB → ECR (единственная видимая замена, язык-то другой).
- Команды: `crails` вместо `rails` (`crails new`, `crails server`,
  `crails generate`, `crails console`, `crails routes`, `crails db:migrate`).

## Производительность: порт ONCE Campfire, официальный verification-harness

Полный порт ONCE Campfire на CRails —
[once-campfire-crails](https://github.com/OrelSokolov/once-campfire-crails) —
замерен официальным harness-ом
[once-campfire-verification](https://github.com/basecamp/once-campfire-verification):
медианный RPS из 3 раундов × 16 конкурентных клиентов, seed-база, каждый
ответ валидируется против route-контракта. CRails — #1 на каждом
замеренном GET-роуте на обоих стендах, включая C и Elixir.

Стенд AMD Ryzen 9 3900X (12 ядер / 24 потока; сервер запинен на 4
аппаратных потока, генератор нагрузки — на отдельных ядрах; одна и та же
seed-база и методология для всех семи приложений):

| Роут | Rails | Express | Go | Rust | C | Elixir | CRails |
|---|---|---|---|---|---|---|---|
| room_show | 1 731 | 10 430 | 14 316 | 21 953 | 31 698 | 2 346 | **38 092** |
| messages_page | 1 641 | 16 248 | 14 336 | 21 539 | 32 114 | 2 480 | **37 553** |
| sidebar | 1 804 | 19 979 | 14 945 | 24 411 | 34 857 | 2 566 | **52 299** |
| search | 1 801 | 17 764 | 15 988 | 25 113 | 33 460 | 2 522 | **48 930** |
| avatar | 28 046 | 40 989 | 48 656 | 74 442 | 18 920 | 31 896 | **76 669** |
| static_css | 37 048 | 42 843 | 59 413 | 72 389 | 37 095 | 36 788 | **75 962** |
| /up | 2 571 | 20 531 | 29 238 | 36 557 | 62 890 | 4 230 | **82 265** |
| post_message | 166 | 1 015 | 2 442 | 2 935 | 1 303 | 556 | 2 033 |

Строка post_message не эквивалентна между приложениями: Express и CRails
персистят каждую джобу уведомлений в leased-SQLite-очередь до отправки
ответа, а Rust и Go гоняют джобы в in-memory-очередях, теряющих работу
при крэше — эта гарантия долговечности и стоит RPS на этом роуте.
Полная методология, результаты ноутбучного стенда и разбор архитектуры
каждой реализации (транспорт, кэши, слой БД):
[README once-campfire-crails](https://github.com/OrelSokolov/once-campfire-crails#benchmark-results).

## License

MIT 
