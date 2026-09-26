# Auth Service

Identity and access management for the platform: users, roles, and OAuth applications, behind one HTTP API.

Auth Service is one Rails app that owns **who a user is**, **what an application may do**, and **whether a token is still good right now**. Client apps delegate authentication and authorization to it instead of each growing their own user table.

## What this is

- Registration, email confirmation, password reset, profile — the only human UI it has, plus the OAuth consent screen.
- OAuth 2.0 authorization server: client apps get tokens for users, and for themselves.
- Single source of truth for users, roles, and OAuth applications.
- An HTTP API for user and application management, consumed by an admin app that lives elsewhere. **Auth Service builds no admin UI.**
- Live token validation: an app asks Auth Service "is this still authorized?" and gets the answer for *now*, not for whenever the token was issued.

## What this is *not*

- Not a token store. Tokens belong to the client that requested them.
- Not a resource server for domain data. It knows users and apps, nothing else.
- Not a role/permission engine. A role is a name. Client apps decide what it means.
- Not a browser-facing service. No CORS, no SPA, no public clients.

## Stack

| Layer | Choice | Latest version |
|---|---|---|
| Runtime | Ruby | 4.0.7 |
| Framework | Rails (full, not `--api`) | 8.1.4 |
| Database | PostgreSQL | 18.6 |
| Auth (humans) | Devise | 5.0.4 |
| Auth (OAuth 2.0) | Doorkeeper | 5.9.9 |
| Token format | opaque + RFC 7662 introspection | — |
| Jobs / cache / cable | Solid Queue / Solid Cache / Solid Cable | 1.7.0 / 1.0.10 / 4.1.0 |
| App server | Puma | 8.0.2 |
| Password hashing | bcrypt | 3.1.22 |
| pg adapter | pg | 1.6.3 |
| Runtime image | `ruby:4.0.7-slim` (Debian slim) | — |
| Dev container | devcontainer, same slim base | — |
| Database image | `postgres:18` | — |
| Tests | Minitest + fixtures (Rails default) | — |

Deliberately **not** in the stack: `doorkeeper-jwt`, `doorkeeper-openid_connect`, `jwt`, `rack-cors`, `pundit`, `rolify`, `cancancan`, `factory_bot`, `rspec`, `sidekiq`, `redis`.

### Gemfile

```ruby
source "https://rubygems.org"

ruby ">= 4.0"

# The only pinned gem. Everything else tracks latest.
gem "rails", "~> 8.1.4"

gem "pg"

# Auth
gem "devise"
gem "doorkeeper"

# Rails 8 defaults
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

gem "puma"
gem "bcrypt"
```

No test gems: Minitest and fixtures ship with Rails, and they are enough for what Auth Service needs — model validations, the introspection response shape, the role mapping, and revocation.

### Version policy

Verified 2026-09-27 against rubygems.org and the projects' release feeds, and the whole set resolves in one `bundle lock` with no conflicts.

- **Only Rails is pinned.** Everything else tracks latest. `Gemfile.lock` is what actually pins the build, so the tree stays deterministic between `bundle update` runs — but an unpinned gem means `bundle update` can cross a major on Devise or Doorkeeper. Run it deliberately, never in CI, and let the Phase 1 introspection test gate the Doorkeeper bump.
- **Devise 5.0.x exists because of Rails 8.1.** Devise 4.9.4 broke on Rails 8.1 ([#5800](https://github.com/heartcombo/devise/issues/5800)); 5.0.2 fixed it and the test matrix covers Rails 8.1 and Ruby 4.0.
- **Doorkeeper declares `railties >= 5` with no upper bound.** It resolves and works on 8.1.4, but it is not pinned to 8.1 — hold Doorkeeper upgrades behind the Phase 1 introspection test, since that is the seam Auth Service depends on.
- **PostgreSQL 18, not 19.** 19 is still in beta; 18.6 is the current stable and is supported to 2030.
- **Toolchain gap.** The dev machine currently has Ruby 4.0.6 and Rails 8.1.3.1. Rails will resolve up to 8.1.4 via Bundler, but Ruby 4.0.7 needs a toolchain install — do that before `rails new`.
- **Rails 8.1 leaves active support on 2026-10-10** (security support runs to 2027-10-10). Start on 8.1.4 and plan the next-branch bump rather than drifting.
- **`solid_cable` is dead weight here.** It is in the Rails 8 default Gemfile, but the consent screen is a plain form POST and nothing in Auth Service pushes a websocket. Drop it during `rails new` (`--skip-action-cable`) unless you have a reason to keep it.

## Container & dev environment

Both images are Debian slim from the official `ruby:$RUBY_VERSION-slim`. That is already what Rails generates for production, so the production Dockerfile needs no editing and only the devcontainer deviates from the Rails default.

| | Image |
|---|---|
| Production | `docker.io/library/ruby:$RUBY_VERSION-slim` |
| Dev container | `docker.io/library/ruby:$RUBY_VERSION-slim` |
| Database, both, as a sidecar | `postgres:18` |

### Production

`rails new` writes a multi-stage `Dockerfile` already based on `ruby-slim`: a throw-away build stage with the compilers, a final stage carrying only runtime packages, gems and app copied across, jemalloc preloaded via `LD_PRELOAD`, and a non-root `rails` user at uid/gid 1000. Left alone it is correct. The package split it uses for PostgreSQL:

```dockerfile
# runtime stage
curl postgresql-client libvips libjemalloc2

# build stage only — thrown away
build-essential git pkg-config libyaml-dev libpq-dev libvips
```

Of the gems in this stack, only `bcrypt` compiles a C extension. `pg` and `sqlite3` both ship precompiled `x86_64-linux` gems, so the entire build stage exists for `bcrypt` and `libyaml-dev`. Drop those two dependencies and the multi-stage split stops earning its keep.

Do not install `tzdata`, Node, or Ruby by hand — the base image already has Ruby 4.0, and compiling Ruby in a container is a permanent maintenance cost for nothing.

### Dev container

Rails generates `.devcontainer/Dockerfile` from `ghcr.io/rails/devcontainer/images/ruby:$RUBY_VERSION`, a Rails-maintained image that is **not** slim. To put dev and prod on one base, point it at the slim image:

```dockerfile
# .devcontainer/Dockerfile
ARG RUBY_VERSION=4.0.7
FROM docker.io/library/ruby:$RUBY_VERSION-slim

# Accessible from outside the container
ENV BINDING="0.0.0.0"
```

That is the whole trade: identical base images, and in exchange you install what the Rails image ships with:

```dockerfile
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential git curl pkg-config libyaml-dev \
      postgresql-client libpq-dev libvips && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives
```

`build-essential` is the load-bearing one: without it `bundle install` fails on `bcrypt`. `git` is needed by devcontainer features and `bin/setup`. The rest come from Rails' own list — keep them, but they only matter if something actually builds against them.

Two more gaps versus the Rails image: `ruby-slim` has no `vscode` user, so the container runs as root unless you create one — fine for dev, and the reason `remoteUser` stays commented out in `devcontainer.json`. And there is no Chromium, so either keep the `selenium` service in `.devcontainer/compose.yaml` or skip system tests. Everything else in the generated `devcontainer.json`, `compose.yaml`, and the `bin/setup --skip-server` post-create hook works unchanged.

**Bump the database tag.** Rails 8.1.3.1 still writes `image: postgres:16.1`, which is from January 2024. Match production:

```yaml
  postgres:
    image: postgres:18
    restart: unless-stopped
    volumes:
      - postgres-data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
```

Postgres runs as a sidecar in both environments, so neither image needs a local server — only `postgresql-client` for `psql` and `libpq-dev` for the `pg` gem.

## Architecture

```
                       ┌──────────────────────────────────┐
   browser ───────────▶│  Auth Service                    │
   (login, signup,     │                                  │
    consent)           │  Devise      users, sessions     │
                       │  Doorkeeper  /oauth/*            │
                       │  Admin API   /api/v1/*           │
                       └───┬──────────────────────┬───────┘
                           │                      │
   POST /oauth/introspect  │                      │  /api/v1/*
   POST /oauth/token       │                      │
   POST /oauth/revoke      │                      │
              ┌────────────┴──────────┐  ┌────────┴─────────┐
              │  client apps          │  │  admin app       │
              │  (backends acting for │  │  (management UI, │
              │   a user or for them- │  │   holds admin    │
              │   selves)             │  │   scopes)        │
              └───────────────────────┘  └──────────────────┘
```

### Three kinds of actor

| | User token | Service token | Resource server |
|---|---|---|---|
| Grant | `authorization_code` + PKCE | `client_credentials` | `client_credentials` |
| Represents | a human + their role | an application | an application asking a question |
| Requested by | a client app, for a user | a client app, for itself | any client app validating a token |
| Token TTL | 15 min + rotating refresh | 15 min | — |

All clients are confidential backends. There is no SPA, no `implicit` grant, and no CORS configuration.

## Validation — the part that matters

Every app that needs to validate tokens registers itself as a Doorkeeper application with the `client_credentials` grant. To check a token it calls:

```
POST /oauth/introspect
Authorization: Basic <its own client_id:client_secret>
token=<token under test>

→ { "active": true,
    "sub": "42",
    "email": "ada@example.com",
    "email_verified": true,
    "first_name": "Ada",
    "last_name": "Lovelace",
    "role": "staff",
    "scope": "read:profile",
    "client_id": "...",
    "iat": 1234567000,
    "exp": 1234567890 }
```

One hop, always live, revocable immediately. No key distribution, no clock skew.

### Two Doorkeeper defaults you must override

**1. `sub` is missing by default.** Doorkeeper's introspection response contains only `active`, `scope`, `client_id`, `token_type`, `iat`, `exp`. There is no `sub` and no `username`, so a client app cannot learn *which* user holds the token — or anything else about them. Everything user-shaped rides in through this hook:

```ruby
# config/initializers/doorkeeper.rb
Doorkeeper.configure do
  custom_introspection_response do |token, _context|
    next nil if token.resource_owner_id.nil? # client_credentials token: an app, not a user

    user = User.find_by(id: token.resource_owner_id)
    # A token whose resource owner no longer exists is dead, not an app token.
    # Returning `{ active: false }` flips the merged response, since
    # Doorkeeper starts from `active: true` and merges this hook over it.
    user ? user.introspection_claims : { active: false }
  end
end
```

Use `User.find_by`, not `token.resource_owner`. That association only exists when `use_polymorphic_resource_owner` is enabled, which is **off by default and needs an extra `resource_owner_type` column**.

A `client_credentials` token has `resource_owner_id == nil`. Client apps must treat `sub: nil` as "this is an app, not a user" — the default response would otherwise have made the two indistinguishable. `&.introspection_claims` would have broken that contract: a deleted user's token has a non-nil `resource_owner_id` and no row, so it would also have answered `active: true` with no `sub` — an app token and an orphaned user token, indistinguishable. **Revoke a user's tokens when the user is destroyed** so the `active: false` branch is a backstop, not the normal path:

```ruby
# app/models/user.rb
has_many :access_tokens, class_name: "Doorkeeper::AccessToken",
                         foreign_key: :resource_owner_id, dependent: :destroy
has_many :access_grants, class_name: "Doorkeeper::AccessGrant",
                         foreign_key: :resource_owner_id, dependent: :destroy
```

**2. Cross-app introspection is denied by default.** Doorkeeper's default rule is `authorized_client.id == token.application_id`: an app may only introspect tokens issued *to itself*. App B asking about a token issued to App A gets `active: false` — a silent, correct-looking, wrong answer. Since every app must be able to validate every user token:

```ruby
Doorkeeper.configure do
  allow_token_introspection do |token, authorized_client, _authorized_token|
    authorized_client.present? # any registered app may introspect
  end
end
```

Being a registered application *is* the authorization to ask. Don't cache the response; add caching only when the hop measurably hurts, and know that the cache TTL becomes your revocation window.

### Which user fields to send

Only send columns that exist. What Devise's generator creates is not a fixed set — it depends on the module list, so the columns below are the ones the modules in *Development notes* actually produce: `email`, `encrypted_password`, `reset_password_token`, `reset_password_sent_at`, `sign_in_count`, `current_sign_in_at`, `last_sign_in_at`, `current_sign_in_ip`, `last_sign_in_ip`, `confirmation_token`, `confirmed_at`, `confirmation_sent_at`, `failed_attempts`, `unlock_token`, `locked_at` — plus Rails' `created_at` and `updated_at`. `remember_created_at` needs `:rememberable` and `unconfirmed_email` needs `:reconfirmable`; neither is enabled, so neither column exists. Of the columns that do, the usable ones for describing a user are `email` and `confirmed_at`. Names are yours to add — see *Adding name fields*.

Use the **JWT/OIDC claim names** rather than your column names where a standard one exists: RFC 7662 §2.2 says extension fields should follow the JWT claim set, so `email_verified` rather than `confirmed`, and `updated_at` rather than `profile_updated_at`. The payoff is that if you later enable `doorkeeper-openid_connect` or JWKS, those two need no mapping and no client app changes. The name claims are the exception, for the reason in *Adding name fields*.

```ruby
# app/models/user.rb

# Whitelist only. Never `as_json` — a Devise model carries encrypted_password,
# reset_password_token, confirmation_token, and the trackable IP columns,
# all of which would go straight to every client app.
def introspection_claims
  {
    sub: id.to_s,                    # Devise has no username column; id is the subject
    email: email,                    # database_authenticatable
    email_verified: confirmed_at.present?, # confirmable
    first_name: first_name,          # the name columns you add
    last_name: last_name,
    updated_at: updated_at.to_i,     # Rails timestamp, OIDC claim name
    role: role,                      # ours, not Devise's
  }
end
```

- `email_verified` comes from `confirmed_at` under `:confirmable`, and it is live, because introspection is live.
- **Deliberately excluded: the whole `:trackable` set.** `sign_in_count`, `last_sign_in_at`, and especially `last_sign_in_ip` and `current_sign_in_ip` are for your own abuse detection. Broadcasting them to every client app is a privacy leak with no authorization use case. Same reasoning for `reset_password_token`, `confirmation_token`, `unlock_token`, `reset_password_sent_at`, and `encrypted_password`.
- **Devise has no name fields.** Nothing in the generator creates `first_name`, `last_name`, `given_name`, or `name` — you add them yourself, in *Adding name fields* below.
- `role` is a column you add yourself. It is the one non-Devise field in the response, and it is the one that matters most.
- **The whitelist is the security boundary, so it gets a test.** The exact-set assertion means adding a claim is always deliberate:

```ruby
# test/models/user_test.rb
def test_introspection_claims_are_whitelisted
  claims = users(:confirmed_staff).introspection_claims
  assert_equal %i[sub email email_verified first_name last_name updated_at role], claims.keys
end
```

**Cost:** one extra `SELECT` per introspection, and introspection runs on every request in every app. It was already one query to resolve the role; the extra fields are free once the row is loaded. The cache decision stands — the moment you cache, the TTL is your revocation window, and it now also freezes the user's email for that window. **Don't log introspection response bodies** — they carry PII now, and `config.filter_parameters` only covers params, not responses.

### Adding name fields

Devise creates no name columns, so this migration is yours:

```ruby
# db/migrate/20260927000000_add_name_to_users.rb
class AddNameToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :first_name, :string, null: false
    add_column :users, :last_name, :string, null: false
  end
end
```

**Both columns are `NOT NULL`, so both are genuinely required.** The DB constraint is the backstop; a model validation is what turns a constraint violation into a form error instead of a 500:

```ruby
# app/models/user.rb
validates :first_name, :last_name, presence: true
```

Two consequences you are choosing: registration must ask for both names, and `POST /api/v1/users` must supply both. If you want the columns `NOT NULL` but the names optional, use `default: ""` instead of presence validations — that is Devise's own convention for `email`. The trade is that `""` becomes the sentinel for "missing", so `ORDER BY last_name` sorts the nameless to the top. Adding this to a populated table would also need a backfill between the `add_column` and the constraint; Auth Service has no users yet, so one `change` block is fine.

**Devise silently drops these params until you permit them.** No error, no warning — the form just saves nothing, and the bug shows up as "the profile page is broken":

```ruby
# app/controllers/application_controller.rb
before_action :configure_permitted_parameters, if: :devise_controller?

protected

def configure_permitted_parameters
  devise_parameter_sanitizer.permit(:sign_up, keys: [:first_name, :last_name])
  devise_parameter_sanitizer.permit(:account_update, keys: [:first_name, :last_name])
end
```

**Names keep their column names.** `first_name` and `last_name` go out as-is, so the claims match the schema with no translation layer to drift. The cost lands at the OIDC boundary: `email_verified` and `updated_at` already match standard claim names, but these two would need mapping to `given_name`/`family_name` in one place when you enable `doorkeeper-openid_connect`. One mapping there, once — not a column rename now.

**Still no composed `name`:** OIDC defines one, but building it is locale-dependent — family-name-first across much of East Asia, family-given in Hungarian, a mononym elsewhere. Baking "first last" into an authorization response imposes a presentation rule on every client app. Auth Service reports the two parts; each client app composes what it displays.

The same argument cuts against two columns: if nothing ever sorts by surname or addresses a user formally, a single `name` column is simpler **and** more correct across locales. You asked for both parts, so here they are as two columns — worth revisiting if name stays display-only.

## Roles

Roles are a single string column on `users`. No gem, no join tables, no policy DSL. Auth Service reports the name; each client app maps the name to its own rules.

```ruby
# db/migrate/20260927000001_add_role_to_users.rb
class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :string, null: false, default: "user"
    add_check_constraint :users, "role IN ('user', 'staff', 'admin')", name: "users_role_check"
  end
end
```

```ruby
# app/models/user.rb
enum :role, {
  user:  "user",
  staff: "staff",
  admin: "admin"
}, validate: true
```

`User.roles.keys` is the canonical role list — there is no separate `ROLES` constant to drift out of sync with the enum.

Role changes take effect on the **next request**, because every request is introspected. No waiting for token expiry.

### Enum syntax, and one trap

Rails 8 **removed** the keyword form. The positional form is required:

```ruby
enum :role, [...]    # Rails 8
enum role: [...]     # removed in Rails 8.0, raises
```

`validate: true` is doing two jobs, and you need both. Without it, assigning an unknown role raises `ArgumentError: 'admn' is not a valid role`, which escapes a controller as a 500. With it, the same assignment produces `valid? == false` and a normal form error. It also makes `role` **required** — `nil` fails validation too, which is what a value every authorization decision depends on deserves.

**Never use the array form on a string column.** Measured on Rails 8.1.3.1:

| Definition (string column) | `role` reads | stored in DB | `admin?` |
|---|---|---|---|
| `enum :role, %i[user staff admin]` | `"admin"` | `"2"` | `false` |
| `enum :role, { admin: "admin" }` | `"admin"` | `"admin"` | `true` |
| `enum :role, %i[user staff admin].index_with(&:to_s)` | `"admin"` | `"admin"` | `true` |

The array form maps names to the **integers** 0/1/2 and then serializes them into your string column. Ruby reads back `"admin"` so nothing looks wrong in the console, but the database holds `"2"`, the predicate methods are `false`, and the check constraint rejects the row. It is only correct on an integer column. The explicit hash is the fix, and it is the form Rails' own docs use for string-backed enums — the mapping is visible on the page, and `index_with(&:to_s)` is the compact equivalent if you would rather not spell it out.

**Integer backing is the alternative:** `enum :role, { user: 0, staff: 1, admin: 2 }`, where the array form becomes correct. You pay for it in readability — the check constraint turns into `role IN (0, 1, 2)`, so a row in psql no longer says what it means, and the introspection claim needs the label rather than the stored value. String values keep the database self-describing and match what client apps receive.

The enum also generates scopes — `User.user`, `User.staff`, `User.admin`. `User.user` reads badly in queries; pass `scopes: false` if you would rather keep them explicit. The check constraint is a plain constraint rather than a Postgres `ENUM` type on purpose: adding a role is then an ordinary migration, not an `ALTER TYPE` you cannot reverse.

### The contract

Auth Service owns the **set of role names**. Each client app owns the **policy** for those names. A downstream app receives `role: "staff"` and decides for itself what a staff member may do there. It never asks Auth Service what a role means.

Consequences to accept:

- **Role names are a public API.** Every client app hardcodes them. Renaming or removing a role is a breaking change across N apps and needs a deprecation period. Adding a role is safe.
- **No per-app limits.** Every app holding an admin's token carries the admin's full power; one app cannot be distinguished from another. That is the intended trade — one trust level for internal apps. Scopes are the upgrade path if it stops being true.
- **No central policy view.** "What can a staff user do?" is answerable only by grepping the client apps. The audit log (Phase 3) is the mitigation.
- **Fail closed, both directions.** Auth Service validates `role` against `User.roles.keys` (plus a DB check constraint), so a typo can't mint an unknown role. Every client app's role map must default-deny on an unrecognised role name rather than fall through to its own logic.

## Revocation

Non-negotiable, because "still authorized" is a core requirement:

- `POST /oauth/revoke` — a client drops its own token (RFC 7009). Doorkeeper ships this.
- **Password change revokes all of the user's tokens.** Doorkeeper does not do this automatically; wire it in the `User` model.
- **Destroying a user revokes their tokens too** — see the introspection hook above. Same mechanism, `dependent: :destroy`.
- `DELETE /api/v1/users/:id/tokens` — kill every token for a user. Backs the admin app's "sign out everywhere".

Refresh tokens rotate on every use. Doorkeeper does the rotation itself when the generated `previous_refresh_token` column is present: each refresh issues a new token and revokes the one presented, and reusing a spent refresh token raises `InvalidGrantReuse` (a `400 invalid_grant`). It does **not** revoke the rest of the chain — the record links back one step, and nothing walks descendants on reuse. If reuse should kill the whole family, that is custom work: catch `InvalidGrantReuse` and revoke every token descending from the reused value through `previous_refresh_token`. Build it in Phase 1 alongside password-change revocation, or drop the stronger guarantee.

## API surface

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET/POST /users/*` | none / session | Devise registration, confirmation, reset, profile |
| `GET /oauth/authorize` | user session | consent screen |
| `POST /oauth/token` | client secret | `authorization_code`, `refresh_token`, `client_credentials` |
| `POST /oauth/introspect` | client secret | validate a token (RFC 7662) |
| `POST /oauth/revoke` | client secret | revoke a token (RFC 7009) |
| `GET /api/v1/users` | `admin:users` scope | list / read users |
| `POST /api/v1/users` | `admin:users` scope | create a user |
| `PATCH /api/v1/users/:id` | `admin:users` scope | update role, profile, password |
| `DELETE /api/v1/users/:id/tokens` | `admin:users` scope | global sign-out |
| `GET /api/v1/applications` | `admin:apps` scope | list OAuth apps |
| `POST /api/v1/applications` | `admin:apps` scope | register an app, return the secret once |
| `DELETE /api/v1/applications/:id` | `admin:apps` scope | revoke an app |

`/api/v1/*` is a normal Doorkeeper-protected controller. The admin app is itself a Doorkeeper application holding `admin:users admin:apps`, obtained via `client_credentials`. No second token scheme, no API keys.

**Bootstrap problem:** the first admin app can't be created through the admin API. Seed it.

```ruby
# db/seeds.rb — idempotent
Doorkeeper::Application.find_or_create_by!(name: "admin") do |app|
  app.redirect_uri = "urn:ietf:wg:oauth:2.0:oob"
  app.scopes = "admin:users admin:apps"
  app.confidential = true
  # ponytail: prints the secret once on first run; rotate it after bootstrapping
  puts "admin client_id=#{app.uid} secret=#{app.secret}"
end
```

Application creation must be **the only** way to get these scopes. No self-service dynamic client registration — on an internal auth service that is a privilege-escalation hole.

## Development notes

Enable these Devise modules: `database_authenticatable`, `registerable`, `recoverable`, `confirmable`, `trackable`, `lockable`, `validatable`. `:lockable` is on because the login form is the platform's one brute-force target, and it is the native way to close that: the columns ship with Devise, the lockout is the module, and no `rack-attack` rule is needed for the account half of the problem. The early lockout option (`maximum_attempts`, `unlock_strategy: :time` plus email unlock) is a config choice, not code. Skip `timeoutable` and `rememberable` — a 15-minute token already bounds a session, and neither has a requirement behind it.

PKCE stays on even though every client is confidential: authorization codes travel through the user's browser, and PKCE is the current best practice for all clients. It is one config line.

## Decisions (locked)

| Decision | Choice | Why |
|---|---|---|
| User login | `authorization_code` redirect + PKCE | Passwords never touch client apps; no deprecated password grant |
| Guaranteeing liveness | every request introspected, uncached | "still authorized" is a requirement, and a cache makes it a lie for its TTL |
| Token format | opaque + introspection | Every app reaches Auth Service at request time; revocation must be immediate; roles must be live |
| JWT / OIDC / JWKS | rejected | Buys nothing without an offline client; costs revocation and key rotation |
| Browser clients / CORS | none | Every client is a backend |
| Roles | Rails `enum` on a string column, name sent in introspection | Client apps only need the name |
| Scopes | Doorkeeper's built-in, used for the app dimension only | Not a user permission model |
| Admin UI | none — API only | Admin app lives in another app |
| RBAC gems | rejected | One column and one hash, not a framework |

## Roadmap

- **Phase 0** — `rails new`, Postgres, Devise (modules above), Doorkeeper with `authorization_code` + PKCE and `client_credentials`. Login + consent screens.
- **Phase 1** — the proof phase. Two initializer overrides (`custom_introspection_response`, `allow_token_introspection`), role column, password-change and user-destroy revocation, refresh-token reuse detection if the whole-chain guarantee stays, and a second real app validating a real token end to end. **Nothing else is worth building until this works.**
- **Phase 2** — `/api/v1`: users, applications, global sign-out, admin app bootstrap seed.
- **Phase 3** — audit log of every grant, revocation, and role change, written in Phase 1's schema. Plus the admin app's audit view.
- **Phase 4** — MFA, `doorkeeper-openid_connect` if an external consumer appears, scopes if per-app limits become real.

## Non-goals

Multi-tenancy, social login, SCIM, LDAP federation, user impersonation, dynamic client registration, a policy DSL.
