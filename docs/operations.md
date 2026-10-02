# Operations

How to run the thing, and where its current edges are.

## Development

`bin/setup` (Rails default) prepares the database and dependencies. After that:

- **`bin/dev`** — Foreman, per `Procfile.dev`: `web` runs `bin/rails server`,
  `vite` runs `bin/vite dev`. Rails lands on port 3000, the Vite dev server on
  3036.
- **`bin/rails test`** — the whole suite. Minitest, no framework.
- **`bin/ci`** — runs `config/ci.rb`: setup, RuboCop, yarn audit,
  Brakeman, tests, seeds.

### Two details in `bin/dev` that are not decoration

- `foreman start -p 3000` is required. Foreman assigns `PORT=5000` to a process
  named `web`, and `config/puma.rb` reads `ENV.fetch("PORT", 3000)` — so without
  `-p 3000` the app silently comes up on 5000 while every document says 3000.
- Vite is configured with `skipProxy: true` (in `config/vite.json`, written by
  `vite install`). With the dev server running, asset tags point straight at
  `http://localhost:3036` — no Rails proxy hop. With it stopped,
  `autoBuild: true` builds on demand and Rails serves `public/vite-dev` locally.
  Both paths work; only the first has HMR.

## Frontend

Vite owns everything: `app/frontend/entrypoints/application.js` and
`.css` are the entry points, built to `public/vite*` (gitignored). Rails'
importmap, propshaft, turbo, and stimulus were removed outright, so:

- **There is no asset pipeline.** `stylesheet_link_tag` and
  `javascript_importmap_tags` are gone from the layout; it uses
  `vite_client_tag` + `vite_javascript_tag`. CSS is imported from JS, not
  listed in a manifest. `config/initializers/assets.rb` is deleted, and so is
  the `config.assets.quiet` line in development.
- **`ApplicationController` no longer calls
  `stale_when_importmap_changes`** — importmap-rails supplied that method.
  HTML etags therefore no longer invalidate on a frontend change.
- **Yarn is the package manager**, through its classic `1.x` line. `vite_ruby`
  resolves the manager by testing for `package-lock.json` before `yarn.lock`, so
  there is no `package-lock.json` here — that is what keeps yarn winning and
  the Dockerfile's `yarn install` consistent with it.
- **Node is a build-time dependency.** `bin/vite build` needs it. That is the
  one place this project contradicts "no Node in containers" — see the
  Dockerfile note below.

## Database: one database per environment

PostgreSQL, one database, shared by the app, Solid Cache, and Solid Queue. There
are no `cache:` or `queue:` entries in `config/database.yml`, no
`migrations_paths`, and no `db/cache_schema.rb` / `db/queue_schema.rb`.

- The Solid tables live in ordinary migrations in `db/migrate`
  (`create_solid_cache_tables`, `create_solid_queue_tables`), so `db/schema.rb`
  carries them: 14 `solid_*` tables.
- Solid Cache rides the primary connection pool — that is the default when
  `config/cache.yml` sets no `database:` key. Setting `database:` or
  `connects_to` there would point it at a second database again.
- Solid Queue likewise: `config.solid_queue.connects_to` must stay **out** of
  `config/environments/production.rb`.
- Production uses `:solid_cache_store` and `:solid_queue` adapter; development
  keeps `:memory_store` and the `:async` adapter, and test keeps `:null_store`.
  Only the topology was consolidated — dev and test were left on Rails' own
  defaults deliberately.
- **`db:migrate` replays `db/schema.rb`, not migrations, on an empty database.**
  After `db:drop db:create`, `bin/rails db:migrate` on a fresh database installs
  the schema file and runs zero migrations — silently, with no output. An edit
  to an already-applied migration is therefore ignored until the schema file is
  out of the way (`mv db/schema.rb` aside for the run) or the change is a new
  migration. This bit the `resource_owner_id` foreign keys once.

To re-verify end to end: boot production against a scratch database, write to
`Rails.cache`, enqueue a job, then run `SolidQueue::Supervisor.start(mode:
:async, standalone: false)` and confirm the job performs and writes back through
the same cache — every step reporting the same `current_database()`.

## Containers

`Dockerfile` is the Rails 8 multi-stage build on `ruby:4.0.7-slim`, held at
`ARG RUBY_VERSION=4.0.7` to match `.ruby-version`. Runtime packages are `curl`,
`postgresql-client`, `libvips`, `libjemalloc2`; the throw-away build stage adds
`build-essential`, `git`, `libpq-dev`, `libvips`, `libyaml-dev`, `pkg-config`,
and — because of Vite — `nodejs` and `npm` (npm installs the pinned Yarn at
build time; only Yarn runs after that). Of the gems here only `bcrypt`
compiles a C extension; `pg` and `sqlite3` ship precompiled `x86_64-linux` gems,
so the build stage exists for `bcrypt`, `libyaml-dev`, and the frontend build.

Where it deviates from stock Rails 8:

- `yarn install --frozen-lockfile` before `COPY . .`, so `node_modules` comes
  from the lockfile.
- `./bin/vite build` **replaces** `rails assets:precompile`. There is no asset
  pipeline gem, so `assets:precompile` does not exist; running it would fail the
  build. Node lands in the discarded stage only, so the final image carries
  neither Node nor `node_modules`.
- `.dockerignore` ignores `/public/vite*`, so a local build cannot leak into the
  image.

Do not install `tzdata` or Ruby by hand — the base image already has Ruby 4.0.
Do not add a Kamal config; deployment orchestration is not this service's
problem, and `kamal` is not in the Gemfile.

### Dev container

`.devcontainer/` holds `devcontainer.json`, `Dockerfile`, and `compose.yaml`,
generated with:

```
bin/rails generate devcontainer --app-name dc-auth --app-folder dc-auth \
  --database postgresql --no-redis --no-system-test --no-active-storage \
  --node --no-kamal
```

It deliberately deviates from that output in six places, because the generator
does not know this app:

| Deviation | Why |
|---|---|
| `FROM docker.io/library/ruby:4.0.7-slim` instead of `ghcr.io/rails/devcontainer/images/ruby` | Dev and production share one base image, so they cannot drift |
| Compilers installed in the Dockerfile | `ruby-slim` has no compilers and `bcrypt` is the one gem here that needs one. `psql` comes from the `postgres-client` feature, not from apt |
| `postgres:18` sidecar instead of `postgres:16.1` | Rails still writes `16.1`, which is from January 2024 |
| `postgres-data` mounted at `/var/lib/postgresql`, not `/var/lib/postgresql/data` | Postgres 18 keeps `PGDATA` in a versioned subdirectory; at the old path the container exits with a mount-point error |
| `3036` added to `forwardPorts` | Vite's dev server, for HMR |
| `postCreateCommand` installs Yarn and runs `yarn install --frozen-lockfile` | `bin/setup` installs gems and prepares the database, not `node_modules`; the `node:1` feature ships npm, not Yarn |

Also unchanged from the generator and worth knowing:

- **Node comes from the `node:1` feature**, which is why the Dockerfile has no
  Node in it — `bin/vite dev` needs Node at runtime, unlike in the production
  image where the build stage is thrown away.
- **`DB_HOST=postgres`** is set in `containerEnv` and read by the default anchor
  in `config/database.yml`. Unset locally, so the pg gem uses the domain socket
  outside the container. This is also why that anchor is ERB.
- **`remoteUser` stays commented out**, as does `user: vscode` in the compose
  file: `ruby-slim` has no `vscode` user, so the container runs as root. That is
  the reason those lines are comments rather than omissions.
- **No Selenium service and no system tests.** `--no-system-test` suppressed both
  the `selenium/standalone-chromium` service and the rewrite of
  `test/application_system_test_case.rb`, which does not exist here. Capybara and
  selenium-webdriver are still in the Gemfile, so enabling them later means
  reversing this one flag.
- **Regenerating overwrites `config/database.yml`** with the generator's
template, losing the single-database production block and the `DB_HOST` anchor.
Back it up first, or reapply those afterwards.

Verified: `docker build -f .devcontainer/Dockerfile .` succeeds on
`ruby:4.0.7-slim`; the `postgres:18` sidecar comes up and accepts the app's
host and credentials through the compose network; `docker compose -f
.devcontainer/compose.yaml config` resolves the bind mount to
`/workspaces/dc-auth`; and `config/database.yml` resolves to the sidecar's host
and credentials only when `DB_HOST` is set. The production image's build stage
was also built end to end (`docker build --target build .`), which is the same
package set plus Node: `bundle install` compiles `bcrypt` there, and
`bin/vite build` runs under Debian's `nodejs`.

## Mail

Confirmation and password-reset mail needs two things the app will not guess:

- **`APP_HOST`** — the host in mailer links. Required in production: the boot
  fails if it is unset rather than mailing `example.com` links. Defaults to
  `localhost` in development and test.

Both are read directly from the process environment. `bin/dev` gets them from
`.env` via Foreman; the production container needs them set in its runtime
environment. SMTP itself is still unconfigured (`config.action_mailer.smtp_settings`
is commented out), so mail does not leave the process yet.

## Known gaps

These are real and currently broken or confusing. They are recorded here rather
than discovered later.

- **`config/initializers/content_security_policy.rb`** has a commented example
  mentioning importmap nonces. Harmless.
- **The human-facing screens are stock gem views.** Login and registration are
  Devise's views; the consent screen is Doorkeeper's. Only the layout is ours.
  The flows work end to end (`test/integration/token_validation_test.rb`), but
  there is no branding or error-message customization yet. See docs/roadmap.md.
