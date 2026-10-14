# propshaft.cr

A port of [propshaft](https://github.com/rails/propshaft) 1.3.2 — the
asset pipeline compiler (pass-through model, no transpilation) — for
CRails.

What it does:

- compiles assets from the load path (`app/assets/*`, `vendor/…`)
  into `public/assets` with digest names (`landing.css` →
  `landing-7f665b1b.css`; the digest is SHA1 of the content plus its
  references, 8 hex characters);
- rewrites `url(...)` in CSS and `RAILS_ASSET_URL("...")` in JS to
  `/assets/<name>-<digest>.<ext>`, and `sourceMappingURL` to the
  digested `.map` path;
- writes `public/assets/.manifest.json`:
  `{"<logical>":{"digested_path":"…","integrity":null}}`;
- precompresses with `.gz`/`.br` siblings (a CRails extension;
  static.cr serves them by Accept-Encoding);
- `clean`/`clobber`/`reveal`.

Serving is handled by `railties_cr`'s `CRails::Middleware::Static`
(a port of Propshaft::Server): in development it resolves against
the load path, in production it serves digest files from
`public/assets`. View-level path resolution lives in
`CRails::PropshaftHelper` (`compute_asset_path` via the
manifest/load path).

## Specs

Oracle-first (see AGENTS.md): a snapshot taken from the real gem —
`oracle/propshaft_expected.yml` (44 cases) — with a mirror in
`spec/propshaft_spec.cr`. The reverse check has the gem verify the
port's output byte for byte (`oracle/verify_propshaft.rb`).

```sh
crystal spec                              # oracle mirror
# reverse (ruby 3.4 + propshaft 1.3.2 in GEM_HOME):
GEM_HOME=… ruby oracle/propshaft_cases.rb > /tmp/x.yml   # snapshot
crystal run spec/reverse_runner.cr -- /tmp/out            # port output
ruby oracle/verify_propshaft.rb oracle/reverse_fixture /tmp/out
```

Deviations from the gem are documented in [PLAN.md](PLAN.md).
