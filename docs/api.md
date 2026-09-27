# API surface

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

The `/oauth/*` and `/users/*` routes are mounted (Phase 0); `/api/v1/*` is not
built yet. See docs/roadmap.md.

`/api/v1/*` is a normal Doorkeeper-protected controller. The admin app is itself
a Doorkeeper application holding `admin:users admin:apps`, obtained via
`client_credentials`. No second token scheme, no API keys, no admin session.

## Bootstrapping the first admin app

The first admin app cannot be created through the admin API, because creating it
requires the scopes it would grant. Seed it, idempotently, in `db/seeds.rb`:
`Doorkeeper::Application.find_or_create_by!(name: "admin")` with a non-http
redirect URI (`urn:ietf:wg:oauth:2.0:oob`), `scopes = "admin:users admin:apps"`,
and `confidential = true`. Print the generated `uid`/`secret` on first run so the
operator can copy it out, then rotate the secret once the admin app is
configured.

Application creation must be **the only** way to get these scopes. No
self-service dynamic client registration — on an internal auth service that is a
privilege-escalation hole (docs/decisions.md, "Non-goals").

## Scope model

Scopes are Doorkeeper's built-in mechanism, used **for the application dimension
only**. They say what an integration is allowed to ask Auth Service for; they are
not a user permission model. Per-user permissions are a client app's business —
Auth Service reports a role name and nothing else (docs/roles.md).

The configured names are `read:profile`, `admin:users`, and `admin:apps`
(`config/initializers/doorkeeper.rb`). Every app must request its scope
explicitly; an application is narrowed to a subset of these at registration.
