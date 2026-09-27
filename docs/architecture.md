# Architecture

## Three kinds of actor

Every party that talks to Auth Service is a confidential backend. There are three
things a caller can be asking for, and they differ only in grant and lifetime:

| | User token | Service token | Resource server |
|---|---|---|---|
| Grant | `authorization_code` + PKCE | `client_credentials` | `client_credentials` |
| Represents | a human + their role | an application | an application asking a question |
| Requested by | a client app, for a user | a client app, for itself | any client app validating a token |
| Token TTL | 15 min + rotating refresh | 15 min | — |

All clients are confidential backends. There is no SPA, no public client, no
`implicit` grant, and therefore no CORS configuration anywhere in the app.

## Shape of the system

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

Auth Service owns exactly three facts: **who a user is**, **what an application
may do**, and **whether a token is still good right now**. Domain data, policy,
and presentation all live in the client apps.

## Why there is no offline validation

The load-bearing decision is that validation is a network hop, every time. See
docs/validation.md for the mechanism and docs/decisions.md for the rejected
alternatives (JWT, JWKS, key rotation, cache TTLs).

Two consequences show up everywhere else in the design:

- **Role and revocation changes take effect on the next request**, not at token
  expiry. This is the reason the service exists in this shape (docs/roles.md,
  docs/revocation.md).
- **Auth Service is on the hot path of every client request.** It is a dependent
  service, not a background authority. Availability and latency matter more here
  than in a typical admin app, and there is no fallback answer but "deny".

## Boundaries

- **No user store in client apps.** One user table, here.
- **No admin UI here.** The admin app is another Doorkeeper application holding
  admin scopes (docs/api.md).
- **No resource-server role.** Auth Service never serves domain data.
- **No role engine.** A role is a string; what it means is each client app's
  business (docs/roles.md).
