# API surface

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /` | none / session | home: sign-in form when anonymous, “you're signed in” page otherwise |
| `GET/POST /users/*` | none / session | Devise registration, confirmation, reset, profile |
| `GET /oauth/authorize` | user session | consent screen |
| `POST /oauth/token` | client secret | `authorization_code`, `refresh_token`, `client_credentials`; adds `id_token` when the grant carries `openid` |
| `POST /oauth/introspect` | client secret | validate a token (RFC 7662) |
| `POST /oauth/revoke` | client secret | revoke a token (RFC 7009) |
| `GET /.well-known/openid-configuration` | none | OIDC discovery document |
| `GET /.well-known/oauth-authorization-server` | none | the same document, at RFC 8414's path |
| `GET /.well-known/webfinger` | none | JRD that echoes `resource` and links the issuer |
| `GET /oauth/discovery/keys` | none | JWKS for the ID token signing key |
| `GET/POST /oauth/userinfo` | bearer token | the user's claims (OIDC Core §5.3) |
| `GET /api/v1/users` | `admin:users` scope | list / read users |
| `POST /api/v1/users` | `admin:users` scope | create a user |
| `PATCH /api/v1/users/:id` | `admin:users` scope | update role, profile, password |
| `DELETE /api/v1/users/:id/tokens` | `admin:users` scope | global sign-out |
| `GET /api/v1/applications` | `admin:apps` scope | list OAuth apps |
| `POST /api/v1/applications` | `admin:apps` scope | register an app, return the secret once |
| `DELETE /api/v1/applications/:id` | `admin:apps` scope | revoke an app |

The `/oauth/*` and `/users/*` routes are mounted (Phase 0); `/api/v1/*` is
built (Phase 2).

`GET /oauth/authorize` without a session sends the user to the sign-in form and
returns them to the consent screen afterwards, query parameters intact — the
return-to is stored by Warden's failure app, so the authenticator must call
`warden.authenticate!`, not `redirect_to`.

`/api/v1/*` is a normal Doorkeeper-protected controller. The admin app is itself
a Doorkeeper application holding `admin:users admin:apps`, obtained via
`client_credentials`. No second token scheme, no API keys, no admin session.

## OIDC

An RP points at `GET /.well-known/openid-configuration`, runs the
`authorization_code` + PKCE flow with `scope=openid profile email`, and gets an
`id_token` alongside the opaque access token. It can then call
`GET /oauth/userinfo` with that access token. The signing key is published at
`/oauth/discovery/keys`. Discovery reports a fixed `issuer` (`APP_HOST`); the
consent screen forwards the RP's `nonce` into the ID token.

This is authentication only. The `id_token` says who the user is and nothing
about what they may do — a client that needs to authorize a request still
introspects the access token, or reads the role name off the token
(docs/validation.md, docs/roles.md).

## `/api/v1` requests and responses

Every request carries `Authorization: Bearer <token>`. A token missing the
endpoint's scope is `403`; no token, an expired one, or a revoked one is `401`.
An unknown `:id` is `404 {error: "not found"}`. The controllers inherit
`ActionController::API` and render JSON.

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

- `secret` is returned by `POST` only, and only as plaintext at creation — it is
  stored hashed and cannot be recovered afterwards (docs/decisions.md). The list
  must never carry it.
- `scopes` is required and must be a subset of the configured scopes
  (`enforce_configured_scopes`); a missing or unknown scope is a `422`.
- `confidential` is always `true` — every client is a backend — and is not
  settable over the API.
- `DELETE` destroys the application; Doorkeeper's `dependent: :delete_all`
  removes its access tokens and grants with it.

## Bootstrapping the first admin app

The first admin app cannot be created through the admin API, because creating it
requires the scopes it would grant. It is created out of band — `db/seeds.rb`
for development, a runner script for production (docs/bootstrap.md) — with a
non-http redirect URI (`urn:ietf:wg:oauth:2.0:oob`),
`scopes = "admin:users admin:apps openid profile email"`, and `confidential =
true`.

Seeding is deliberately **not idempotent**: `create!` raises on a re-run against
a database that already holds these rows, so nothing is silently reused or
skipped. Application secrets are hashed at rest (`hash_application_secrets`), so
the `uid`/`secret` are in plaintext only on the instance that created the row —
capture them then. There is no rotate endpoint: a lost secret means destroying
and recreating the application, which drops its access tokens and grants with
it.

Application creation must be **the only** way to get these scopes. No
self-service dynamic client registration — on an internal auth service that is a
privilege-escalation hole (docs/decisions.md, "Non-goals").

## Scope model

Scopes are Doorkeeper's built-in mechanism, used **for the application dimension
only**. They say what an integration is allowed to ask Auth Service for; they are
not a user permission model. Per-user permissions are a client app's business —
Auth Service reports a role name and nothing else (docs/roles.md).

The configured names are `admin:users`, `admin:apps`, `openid`, `profile`, and
`email` (`config/initializers/doorkeeper.rb`). Every app must
request its scope explicitly; an application is narrowed to a subset of these at
registration.

The three OIDC scopes are inert on a machine-only app: `client_credentials` has
no end user, so no `id_token` is issued and the introspection hook adds nothing
to the response for it.
They exist for the browser flows, and every application holds them so that an RP
can ask for `openid profile email` without a re-registration (docs/validation.md).
