# Roadmap

Phases are ordered by dependency, not by value. Phase 1 is the reason the project
exists; everything after it is plumbing.

## Phase 0 — skeleton and stack (done)

**Done:** `rails new` with PostgreSQL, the dependency set in `Gemfile`, one
database per environment shared with Solid Cache and Solid Queue (see
docs/operations.md), Vite instead of the Rails 8 frontend defaults, and
`bin/dev` running Rails + Vite under Foreman. Ruby 4.0.7 is installed and
pinned. `devise:install` and the `User` model with the module list below; the
`first_name`/`last_name` columns, the `role` column with its check constraint
and enum, and the `introspection_claims` whitelist with its test (docs/validation.md
and docs/roles.md). `doorkeeper:install` with `authorization_code` +
PKCE, `client_credentials`, rotating refresh tokens, a 15-minute TTL, and both
introspection overrides from docs/validation.md. The applications and
authorized-applications controllers are skipped (docs/decisions.md).

**Not done in this phase:** item 4 below, and everything downstream of it.

Remaining Phase 0 work:

1. Login, registration, and the consent screen. These are served by Devise's
   and Doorkeeper's stock views, with the app's own layout. No view files were
   generated — there is nothing customized to maintain yet, and the
   authorization-code flow through them is exercised end to end by
   `test/controllers/token_validation_test.rb` (Phase 1).

The `User` modules are `database_authenticatable`, `registerable`,
`recoverable`, `confirmable`, `trackable`, `lockable`, `validatable`.

- `:lockable` is on because the login form is the platform's one brute-force
  target, and it is the native way to close that: the columns ship with
  Devise, the lockout is the module, and no `rack-attack` rule is needed for
  the account half of the problem. The early-lockout option
  (`maximum_attempts`, `unlock_strategy: :time` plus email unlock) is a config
  choice, not code — still at Devise's defaults.
- `timeoutable` and `rememberable` are skipped — a 15-minute token already
  bounds a session and neither has a requirement behind it. `reconfirmable` is on,
  so changing an email needs the new address confirmed before it applies.

PKCE stays on even though every client is confidential: authorization codes
travel through the user's browser, and PKCE is the current best practice for all
clients. It is one config line.

## Phase 1 — the proof phase (done)

Password-change revocation (`User#revoke_tokens_on_password_change`), and **a
second real app validating a real token end to end**
(`test/controllers/token_validation_test.rb`). User-destroy revocation was
already in place: the foreign keys on `resource_owner_id` forced the
`dependent: :destroy` associations with them (docs/revocation.md).

The whole-chain refresh-token reuse guarantee was **dropped**, not built: a
replayed refresh token fails that one request and nothing else
(docs/revocation.md, docs/decisions.md).

This was the gate for any Doorkeeper upgrade (docs/stack.md).

## Phase 2 — `/api/v1` (done)

Users (list, read, create, update), applications (list, register, revoke),
global sign-out (`DELETE /api/v1/users/:id/tokens`), and the idempotent admin
app seed. Scope-enforced through Doorkeeper's bearer token, no second auth
scheme. Covered by the controller tests under `test/controllers/api/v1/`; shapes
and parameters in docs/api.md.

The admin app's audit view is not here — it is Phase 3.

## Phase 3 — audit log

Every grant, revocation, and role change, written in Phase 1's schema. Plus the
admin app's audit view. This is the mitigation for having no central policy view
(docs/roles.md).

## Phase 4 — optional

MFA. `doorkeeper-openid_connect` if an external consumer appears. Scopes as a
per-user permission model if per-app limits become real.
