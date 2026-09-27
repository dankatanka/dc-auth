# Revocation

"Still authorized" is a core requirement, so revocation is non-negotiable and
immediate. Because validation is live (docs/validation.md), a revoked token stops
working on the next request, not at expiry.

## What must revoke

- **`POST /oauth/revoke`** — a client drops its own token (RFC 7009). Doorkeeper
  ships this.
- **Password change revokes all of the user's tokens.** Doorkeeper does **not**
  do this automatically; it must be wired in the `User` model.
- **Destroying a user revokes their tokens.** `dependent: :destroy` on the
  `Doorkeeper::AccessToken` and `Doorkeeper::AccessGrant` associations keyed by
  `resource_owner_id` (both on `User`). A foreign key on the same columns in
  `create_doorkeeper_tables` backstops it: a delete that skipped the
  associations fails loudly instead of orphaning tokens. Together they keep the
  `custom_introspection_response` missing-user branch (docs/validation.md) a
  backstop rather than the normal path.
- **`DELETE /api/v1/users/:id/tokens`** — kill every token for a user. Backs the
  admin app's "sign out everywhere".

## Refresh token rotation

Refresh tokens rotate on every use. Doorkeeper does the rotation itself when the
generated `previous_refresh_token` column is present: each refresh issues a new
token and revokes the one presented, and reusing a spent refresh token raises
`InvalidGrantReuse` (a `400 invalid_grant`).

It does **not** revoke the rest of the chain on reuse. The record links back one
step, and nothing walks descendants when a spent token is presented again — the
reuse only fails that one request.

If reuse should kill the whole token family, that is custom work: catch
`InvalidGrantReuse` and revoke every token descending from the reused value
through `previous_refresh_token`. Build it in Phase 1 alongside password-change
revocation, or drop the stronger guarantee explicitly (docs/decisions.md).

## Why not cache the introspection answer

A cached introspection response is a lie for the length of its TTL. That is the
whole reason the token format is opaque plus introspection rather than a JWT
(docs/decisions.md). If caching is ever added under measured load, the cache TTL
is the revocation window — and that number needs to be documented here when it
changes, because it silently redefines "revoked".
