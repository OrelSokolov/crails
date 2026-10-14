# propshaft_cr

Порт [propshaft](https://github.com/rails/propshaft) 1.3.2 —
компилятора asset pipeline (pass-through модель, без транспиляции)
для CRails.

Что делает:

- собирает ассеты из load path (`app/assets/*`, `vendor/…`) в
  `public/assets` с digest-именами (`landing.css` →
  `landing-7f665b1b.css`; digest — SHA1 контента + референсов,
  8 hex-символов);
- переписывает `url(...)` в CSS и `RAILS_ASSET_URL("...")` в JS на
  `/assets/<name>-<digest>.<ext>`, `sourceMappingURL` — на digest
  путь `.map`;
- пишет `public/assets/.manifest.json`:
  `{"<logical>":{"digested_path":"…","integrity":null}}`;
- прекомпрессия соседями `.gz`/`.br` (CRails-расширение; static.cr
  отдаёт их по Accept-Encoding);
- `clean`/`clobber`/`reveal`.

Отдача — `railties_cr` `CRails::Middleware::Static` (порт
Propshaft::Server): dev — резолв по load path, prod — digest-файлы из
`public/assets`. Резолвинг во вьюхах — `CRails::PropshaftHelper`
(`compute_asset_path` через манифест/load path).

## Спеки

Оракул-first (AGENTS.md): снимок с настоящего гема —
`oracle/propshaft_expected.yml` (44 кейса), зеркало —
`spec/propshaft_spec.cr`. Реверс-проверка — гем сверяет выход порта
побайтово (`oracle/verify_propshaft.rb`).

```sh
crystal spec                              # зеркало оракула
# реверс (ruby 3.4 + пропshaft 1.3.2 в GEM_HOME):
GEM_HOME=… ruby oracle/propshaft_cases.rb > /tmp/x.yml   # снимок
crystal run spec/reverse_runner.cr -- /tmp/out            # выход порта
ruby oracle/verify_propshaft.rb oracle/reverse_fixture /tmp/out
```

Отклонения от гема — в [PLAN.md](PLAN.md).
