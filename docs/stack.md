# Stack and version policy

## Versions in use

Read from `Gemfile.lock`, `.ruby-version`, `package.json`, and
`config/database.yml`. The Gemfile itself is the source of truth for direct
dependencies — do not copy it here.

| Layer | Choice | Version |
|---|---|---|
| Runtime | Ruby | 4.0.7 (`.ruby-version`; Gemfile requires `>= 4.0`) |
| Framework | Rails (full, not `--api`) | 8.1.4 |
| Database | PostgreSQL | 18 |
| Auth (humans) | Devise | 5.0.4 |
| Auth (OAuth 2.0) | Doorkeeper | 5.9.9 |
| Token format | opaque + RFC 7662 introspection | — |
| Jobs | Solid Queue | 1.7.0 |
| Cache | Solid Cache | 1.0.10 |
| App server | Puma | 8.0.2 |
| Frontend | Vite + vite_rails | 8.3.1 / 3.11.1 (yarn) |
| Dev process runner | Foreman | 0.90.0 |
| Password hashing | bcrypt | 3.1.22 |
| pg adapter | pg | 1.6.3 |
| Production image | `ruby:4.0.7-slim` | Dockerfile |
| Dev container | `.devcontainer/` — same base image, `postgres:18` sidecar | — |
| Tests | Minitest + fixtures (Rails default) | — |

Deliberately **not** in the stack: `solid_cable` and Action Cable (nothing here
pushes a socket), Action Mailbox, Action Text, Active Storage, `propshaft`,
`importmap-rails`, `turbo-rails`, `stimulus-rails`, `image_processing`, `kamal`,
`tzinfo-data`, `bundler-audit`, `doorkeeper-jwt`, `doorkeeper-openid_connect`,
`jwt`, `rack-cors`, `pundit`, `rolify`, `cancancan`, `factory_bot`, `rspec`,
`sidekiq`, `redis`.

There are no test gems. Minitest and fixtures ship with Rails, and they are
enough for what Auth Service needs: model validations, the introspection
response shape, the role mapping, and revocation. See
docs/operations.md for the one test that exists today.

## Why these choices, where it is not obvious

- **Rails full, not `--api`.** The service has a human UI — registration,
  confirmation, password reset, profile, and the OAuth consent screen. `--api`
  would remove the view layer it needs.
- **Devise 5.0.x exists because of Rails 8.1.** Devise 4.9.4 broke on Rails 8.1
  ([#5800](https://github.com/heartcombo/devise/issues/5800)); 5.0.2 fixed it and
  the test matrix covers Rails 8.1 and Ruby 4.0. On Rails 8.1, Devise 5 is not a
  preference, it is the only working version.
- **Doorkeeper declares `railties >= 5` with no upper bound.** It resolves and
  works on 8.1.4, but it is not pinned to 8.1 — hold Doorkeeper upgrades behind
  the Phase 1 introspection test, since that is the seam this service depends on
  (docs/validation.md).
- **PostgreSQL 18, not 19.** 19 is still in beta; 18.x is the current stable and
  is supported to 2030.
- **Opaque tokens + introspection over JWT.** See docs/decisions.md. The short
  version: a JWT buys nothing without an offline client and costs revocation.
- **Vite over the Rails 8 defaults.** Vite is the only frontend toolchain here;
  the importmap/propshaft/turbo/stimulus default set was removed rather than left
  partially wired (docs/operations.md explains the consequences).
- **`solid_cable` was dropped** and Action Cable is not required at all. The
  consent screen is a plain form POST; nothing in Auth Service pushes a
  websocket.

## Version policy

Verified 2026-09-27 against rubygems.org and the projects' release feeds, and the
whole set resolves in one `bundle lock` with no conflicts.

- **Only Rails is pinned**, to `~> 8.1.4`. Everything else tracks latest.
  `Gemfile.lock` is what actually pins the build, so the tree stays deterministic
  between `bundle update` runs — but an unpinned gem means `bundle update` can
  cross a major on Devise or Doorkeeper. Run it deliberately, never in CI, and
  let the Phase 1 introspection test gate the Doorkeeper bump.
- **Rails 8.1 leaves active support on 2026-10-10** (security support runs to
  2027-10-10). Start on 8.1.4 and plan the next-branch bump rather than drifting.
- **Ruby 4.0.7 is installed and used.** The earlier toolchain gap is closed:
  `.ruby-version`, the `Dockerfile` ARG, and `Gemfile.lock`'s RUBY VERSION all
  say 4.0.7.
- **Yarn is the package manager**, not npm. `yarn.lock` is the lockfile; there
  is no `package-lock.json` (docs/operations.md).
