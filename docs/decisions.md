# Decisions (locked) and non-goals

These are settled. Changing one means updating this file and the doc it affects,
not just the code.

| Decision | Choice | Why |
|---|---|---|
| User login | `authorization_code` redirect + PKCE | Passwords never touch client apps; no deprecated password grant |
| Guaranteeing liveness | every request introspected, uncached | "still authorized" is a requirement, and a cache makes it a lie for its TTL |
| Token format | opaque + introspection | Every app reaches Auth Service at request time; revocation must be immediate; roles must be live |
| Refresh-token reuse | the replayed request fails (`400 invalid_grant`); the rest of the chain stays live | Whole-chain revocation is custom error-path code; replay is already caught per-request, and password change is the blunt kill switch when a session must die (docs/revocation.md) |
| JWT / OIDC / JWKS | rejected | Buys nothing without an offline client; costs revocation and key rotation |
| Browser clients / CORS | none | Every client is a backend — no SPA, no public client, no CORS config |
| Roles | Rails `enum` on a string column, name sent in introspection | Client apps only need the name (docs/roles.md) |
| Scopes | Doorkeeper's built-in, used for the app dimension only | Not a user permission model |
| Admin UI | none — API only | The admin app lives in another app |
| RBAC gems | rejected | One column and one hash, not a framework |
| Database topology | one database per environment, shared with Solid Cache and Solid Queue | No cache or queue database to operate (docs/operations.md) |
| Frontend | Vite, yarn | One toolchain; no asset pipeline, no importmaps (docs/operations.md) |
| Deployment | Dockerfile only | `kamal` and `solid_cable` removed; orchestration is not this service's concern |

## On `doorkeeper-openid_connect`

Not enabled. If it is: `email_verified` and `updated_at` already match standard
claim names, so only `first_name`/`last_name` → `given_name`/`family_name` needs
mapping, in one place. That mapping argument is why the name columns keep their
column names (docs/validation.md).

## Non-goals

Multi-tenancy, social login, SCIM, LDAP federation, user impersonation, dynamic
client registration, and a policy DSL.

Two of these are load-bearing rather than merely out of scope:

- **Dynamic client registration** is rejected on security grounds, not effort. On
  an internal auth service it is a privilege-escalation hole: registering an
  application must be the only route to admin scopes, and it is a seeded or
  admin-API operation (docs/api.md).
- **A policy DSL** is rejected because Auth Service deliberately has no opinion
  about what a role means. The contract is a role *name*; policy lives in each
  client app (docs/roles.md).
