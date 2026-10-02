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

The `/oauth/*` and `/users/*` routes are mounted (Phase 0); `/api/v1/*` is
built (Phase 2).

`/api/v1/*` is a normal Doorkeeper-protected controller. The admin app is itself
a Doorkeeper application holding `admin:users admin:apps`, obtained via
`client_credentials`. No second token scheme, no API keys, no admin session.

## `/api/v1` requests and responses

Every request carries `Authorization: Bearer <token>`. A token missing the
endpoint's scope is `403`; no token, an expired one, or a revoked one is `401`.
The controllers inherit `ActionController::API` and render JSON.

Users, `admin:users`:

```
GET    /api/v1/users            → [{id, email, first_name, last_name, role, confirmed_at, created_at, updated_at}, …]
GET    /api/v1/users/:id        → { …same… }
POST   /api/v1/users            ← {user: {email, first_name, last_name, role?, password, password_confirmation}}
                                → 201 { …user… } | 422 {errors: ["…"]}
PATCH  /api/v1/users/:id        ← {user: {email?, first_name?, last_name?, role?, password?, password_confirmation?}}
                                → 200 { …user… } | 422 {errors: ["…"]}
DELETE /api/v1/users/:id/tokens → 204
```

- `first_name`, `last_name`, and `password` are required on create — the columns
  are `NOT NULL` and Devise's `:validatable` needs a password.
- A created user is unconfirmed: `:confirmable` mails the instructions, and
  `confirmed_at` stays null until they follow them.
- `role` defaults to `customer`. An unknown role is a `422`, not the `ArgumentError`
  a 500 comes from (docs/roles.md).
- No response carries `encrypted_password` or any token.
- Global sign-out revokes every access token and pending access grant for the
  user (docs/revocation.md).

Applications, `admin:apps`:

```
GET    /api/v1/applications      → [{id, name, uid, scopes, redirect_uri, confidential, created_at}, …]
POST   /api/v1/applications      ← {application: {name, redirect_uri, scopes}}
                                 → 201 { …application…, secret } | 422
DELETE /api/v1/applications/:id  → 204
```

- `secret` is returned by `POST` only; the list must never carry it.
- `scopes` must be a subset of the configured scopes
  (`enforce_configured_scopes`); an unknown scope is a `422`.
- `confidential` is always `true` — every client is a backend — and is not
  settable over the API.
- `DELETE` destroys the application; Doorkeeper's `dependent: :delete_all`
  removes its access tokens and grants with it.

## Bootstrapping the first admin app

The first admin app cannot be created through the admin API, because creating it
requires the scopes it would grant. `db/seeds.rb` creates it with
`Doorkeeper::Application.create!` and a non-http redirect URI
(`urn:ietf:wg:oauth:2.0:oob`), `scopes = "admin:users admin:apps"`, and
`confidential = true`.

Seeding is deliberately **not idempotent**: `create!` raises on a re-run against
a database that already holds these rows, so nothing is silently reused or
skipped. The generated `uid`/`secret` are not printed; read them with
`Doorkeeper::Application.find_by!(name: "admin")`, then rotate the secret once
the admin app is configured.

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
