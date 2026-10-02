# Auth Service

Identity and access management for the platform: users, roles, and OAuth
applications, behind one HTTP API. Client apps delegate authentication and
authorization to it instead of each growing their own user table.

> **Status: Phase 1 done — the proof phase.** The skeleton, database, and
> dependency stack are in place and verified. The `User` model (roles, names,
> claim whitelist) and the OAuth endpoints are wired — `authorization_code` +
> PKCE, `client_credentials`, rotating refresh, and both introspection overrides.
> Password change revokes every token, and a second registered app validates a
> real user token end to end
> (`test/integration/token_validation_test.rb`). The human-facing screens are the
> gems' stock views, not yet customized. See [docs/roadmap.md](docs/roadmap.md).

## What this is

- Registration, email confirmation, password reset, profile — the only human UI
  it has, plus the OAuth consent screen.
- OAuth 2.0 authorization server: client apps get tokens for users, and for
  themselves.
- Single source of truth for users, roles, and OAuth applications.
- An HTTP API for user and application management, consumed by an admin app that
  lives elsewhere. **Auth Service builds no admin UI.**
- Live token validation: an app asks Auth Service "is this still authorized?"
  and gets the answer for *now*, not for whenever the token was issued.

## What this is *not*

- Not a token store. Tokens belong to the client that requested them.
- Not a resource server for domain data. It knows users and apps, nothing else.
- Not a role/permission engine. A role is a name. Client apps decide what it means.
- Not a browser-facing service. No CORS, no SPA, no public clients.

## Stack

| Layer | Choice |
|---|---|
| Runtime | Ruby 4.0.7 |
| Framework | Rails 8.1.4 (full, not `--api`) |
| Database | PostgreSQL 18 — **one** database per environment, shared with Solid Cache and Solid Queue |
| Auth (humans) | Devise 5.0.4 |
| Auth (OAuth 2.0) | Doorkeeper 5.9.9, opaque tokens + RFC 7662 introspection |
| Frontend | Vite (yarn); no asset pipeline, no importmaps |
| Jobs / cache | Solid Queue 1.7.0 / Solid Cache 1.0.10 |
| App server | Puma 8.0.2, Thruster in the image |
| Dev container | `.devcontainer/` — same `ruby:4.0.7-slim` base, `postgres:18` sidecar |
| Tests | Minitest + fixtures |

Versions, why each was chosen, and what was deliberately left out:
[docs/stack.md](docs/stack.md).

## Documentation

| Doc | Covers |
|---|---|
| [architecture.md](docs/architecture.md) | The three actor kinds, system shape, boundaries |
| [validation.md](docs/validation.md) | Introspection, the two Doorkeeper overrides, claim whitelist, name fields |
| [roles.md](docs/roles.md) | Role column, the string-enum trap, the role contract |
| [revocation.md](docs/revocation.md) | What must revoke and when, refresh rotation |
| [api.md](docs/api.md) | Endpoint table, scopes, admin app bootstrap |
| [operations.md](docs/operations.md) | Dev workflow, frontend, database topology, Dockerfile, known gaps |
| [stack.md](docs/stack.md) | Versions, version policy, rejected dependencies |
| [roadmap.md](docs/roadmap.md) | Phase 0–1 status and Phases 2–4 |
| [decisions.md](docs/decisions.md) | Locked decisions and non-goals |
| [coding-style.md](docs/coding-style.md) | Code is not docs, and what a comment is for |

## Running it

```sh
bin/setup        # dependencies and database
bin/dev          # Rails on :3000 + Vite on :3036, via Foreman
bin/rails test   # Minitest suite
```

Details, including why `bin/dev` pins the port and what is currently broken in
CI: [docs/operations.md](docs/operations.md).
