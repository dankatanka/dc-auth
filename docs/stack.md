# Stack and version policy

## Versions in use

The `Gemfile` is the source of truth for direct dependencies; `Gemfile.lock`
pins the build. This table records the major line each choice is on, not the
patch in the lockfile — patch numbers rot faster than anything else in `docs/`,
so look them up in the lockfile when they matter.

| Layer | Choice |
|---|---|
| Runtime | Ruby 4.0 (`.ruby-version`; Gemfile requires `>= 4.0`) |
| Framework | Rails 8.1 (full, not `--api`) |
| Database | PostgreSQL 18 |
| Auth (humans) | Devise 5 |
| Auth (OAuth 2.0) | Doorkeeper 5, opaque tokens + RFC 7662 introspection |
| Auth (OIDC) | doorkeeper-openid_connect 2, RS256 ID tokens |
| Jobs / cache | Solid Queue 1 / Solid Cache 1 |
| App server | Puma 8 |
| Frontend | Vite 8 + vite_ruby 3 (yarn) |
| Dev process runner | Foreman |
| Password hashing | bcrypt |
| pg adapter | pg |
| Production image | `ruby:4.0-slim` (see `Dockerfile`) |
| Dev container | `.devcontainer/` — same base image, `postgres:18` sidecar |
| Tests | Minitest + fixtures (Rails default) |

Deliberately **not** in the stack: `solid_cable` and Action Cable (nothing here
pushes a socket), Action Mailbox, Action Text, Active Storage, `propshaft`,
`importmap-rails`, `turbo-rails`, `stimulus-rails`, `image_processing`, `kamal`,
`thruster`, `tzinfo-data`, `bundler-audit`, `doorkeeper-jwt`, `rack-cors`,
`pundit`, `rolify`, `cancancan`, `factory_bot`, `rspec`, `sidekiq`, `redis`.

There are no test frameworks. Minitest and fixtures ship with Rails, and they
are enough for what Auth Service needs: model validations, the introspection
response shape, the role mapping, and revocation. See docs/operations.md for
how to run them. Capybara and selenium-webdriver are in the `test` group but
unused while there are no system tests (docs/operations.md).

## Why these choices, where it is not obvious

- **Rails full, not `--api`.** The service has a human UI — registration,
  confirmation, password reset, profile, and the OAuth consent screen. `--api`
  would remove the view layer it needs.
- **Devise 5 exists because of Rails 8.1.** Devise 4.9 broke on Rails 8.1
  ([#5800](https://github.com/heartcombo/devise/issues/5800)); the 5.0 line fixed
  it and the test matrix covers Rails 8.1 and Ruby 4.0. On Rails 8.1, Devise 5
  is not a preference, it is the only working version.
- **Doorkeeper declares `railties >= 5` with no upper bound.** It resolves and
  works on 8.1, but it is not pinned to 8.1 — hold Doorkeeper upgrades behind
  the Phase 1 introspection test, since that is the seam this service depends on
  (docs/validation.md).
- **PostgreSQL 18, not 19.** 19 is still in beta; 18.x is the current stable and
  is supported to 2030.
- **Opaque tokens + introspection over JWT.** See docs/decisions.md. The short
  version: a JWT buys nothing without an offline client and costs revocation.
- **`doorkeeper-openid_connect` for the OIDC surface.** It is the reference
  implementation on top of the Doorkeeper already here, and it only adds
  `id_token`/discovery/userinfo — it does not change the token format, so the
  introspection path stays the one this service is built around
  (docs/validation.md).
- **Vite over the Rails 8 defaults.** Vite is the only frontend toolchain here;
  the importmap/propshaft/turbo/stimulus default set was removed rather than left
  partially wired (docs/operations.md explains the consequences).
- **`solid_cable` was dropped** and Action Cable is not required at all. The
  consent screen is a plain form POST; nothing in Auth Service pushes a
  websocket.
- **Thruster was dropped.** It buys gzip, X-Sendfile, and static-file caching in
  front of Puma; there is no Active Storage here, the app answers with one form
  and JSON, and Puma serves `public/` on its own. It cost a supervisor process
  and a `:80` binding uid 1000 cannot have. Compression and caching, if they are
  ever wanted, belong to the ingress.

## Version policy

- **Only Rails is pinned**, to the 8.1 line. Everything else tracks latest.
  `Gemfile.lock` is what actually pins the build, so the tree stays deterministic
  between `bundle update` runs — but an unpinned gem means `bundle update` can
  cross a major on Devise or Doorkeeper. Run it deliberately, never in CI, and
  let the Phase 1 introspection test gate the Doorkeeper bump.
- **Rails 8.1 leaves active support in October 2026** (security support runs to
  October 2027). Plan the next-branch bump rather than drifting.
- **Ruby 4.0 is installed and used.** `.ruby-version`, the `Dockerfile` ARG, and
  `Gemfile.lock`'s RUBY VERSION agree on the 4.0 line.
- **Yarn is the package manager**, not npm. `yarn.lock` is the lockfile; there
  is no `package-lock.json` (docs/operations.md).
