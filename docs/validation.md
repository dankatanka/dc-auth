# Validation — the part that matters

Every app that needs to validate tokens registers itself as a Doorkeeper
application with the `client_credentials` grant. To check a token it calls:

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

## Two Doorkeeper defaults you must override

Doorkeeper ships nothing here that is usable as-is. Both overrides are
security-relevant, not cosmetic, and both belong in
`config/initializers/doorkeeper.rb` (see docs/roadmap.md).

### 1. `sub` is missing by default

Doorkeeper's introspection response contains only `active`, `scope`,
`client_id`, `token_type`, `iat`, `exp`. There is no `sub` and no `username`, so
a client app cannot learn *which* user holds the token — or anything else about
them. Everything user-shaped has to ride in through the
`custom_introspection_response` hook.

The hook must answer three different cases correctly, and the naive version gets
two of them wrong:

| Token | Wanted answer | Trap |
|---|---|---|
| user token, user exists | the user's claims | — |
| `client_credentials` token | `active: true`, no `sub` | must not look up a user |
| user token, user deleted | `active: false` | must not answer "active, no sub" |

Resolve the user with `User.find_by(id: token.resource_owner_id)`. Do **not** use
`token.resource_owner`: that association only exists when
`use_polymorphic_resource_owner` is enabled, which is off by default and needs an
extra `resource_owner_type` column.

A `client_credentials` token has `resource_owner_id == nil`. Client apps must
treat `sub: nil` as "this is an app, not a user". The tempting `&.introspection_claims`
breaks that contract: a deleted user's token has a non-nil `resource_owner_id`
and no row, so it would also answer `active: true` with no `sub` — an app token
and an orphaned user token, indistinguishable. Return `{ active: false }` for
the missing-user case; Doorkeeper starts from `active: true` and merges the hook
over it, so returning `active: false` flips the whole response.

**Revoke a user's tokens when the user is destroyed** (docs/revocation.md) so the
`active: false` branch is a backstop, not the normal path.

### 2. Cross-app introspection is denied by default

Doorkeeper's default rule is `authorized_client.id == token.application_id`: an
app may only introspect tokens issued *to itself*. App B asking about a token
issued to App A gets `active: false` — a silent, correct-looking, wrong answer.
Since every app must be able to validate every user token, override
`allow_token_introspection` to allow any registered client. Being a registered
application *is* the authorization to ask.

Do not cache the response. Add caching only when the hop measurably hurts, and
know that the cache TTL becomes your revocation window — and now also freezes
the user's email and role for that window.

## Which user fields to send

Send only columns that exist, and only ones a client app can act on. What
Devise's generator creates is not a fixed set — it depends on the module list,
so this is defined by the modules in docs/roadmap.md (Phase 0):
`email`, `encrypted_password`, `reset_password_token`,
`reset_password_sent_at`, `sign_in_count`, `current_sign_in_at`,
`last_sign_in_at`, `current_sign_in_ip`, `last_sign_in_ip`, `confirmation_token`,
`confirmed_at`, `confirmation_sent_at`, `failed_attempts`, `unlock_token`,
`locked_at`, plus Rails' `created_at` and `updated_at`, and `unconfirmed_email`
for the pending address under `:reconfirmable`. `remember_created_at` needs
`:rememberable`, which is off, so that column is absent.

Of those, the usable ones for describing a user are `email` and `confirmed_at`.
Names and role are columns we add ourselves.

### Use JWT/OIDC claim names

RFC 7662 §2.2 says extension fields should follow the JWT claim set, so
`email_verified` rather than `confirmed`, and `updated_at` rather than
`profile_updated_at`. The payoff is that if `doorkeeper-openid_connect` or JWKS
is ever enabled, those claims need no mapping and no client app changes. The name
claims are the deliberate exception (below).

The response is built by a **whitelist** method on `User` — `introspection_claims`
— and never by `as_json`. A Devise model carries `encrypted_password`,
`reset_password_token`, `confirmation_token`, and the trackable IP columns, all
of which would otherwise go straight to every client app.

Fields sent: `sub` (from `id`, since Devise has no username column), `email`,
`email_verified` (from `confirmed_at.present?`), `first_name`, `last_name`,
`updated_at` (as an epoch integer), `role`.

Deliberately excluded, and why:

- **The whole `:trackable` set.** `sign_in_count`, `last_sign_in_at`, and
  especially `last_sign_in_ip` / `current_sign_in_ip` are for our own abuse
  detection. Broadcasting them to every client app is a privacy leak with no
  authorization use case.
- **`reset_password_token`, `confirmation_token`, `unlock_token`,
  `reset_password_sent_at`, `encrypted_password`.** Same reasoning.

`email_verified` comes from `confirmed_at` under `:confirmable`, and it is live,
because introspection is live.

### The whitelist is the security boundary, so it gets a test

An exact-set assertion, so adding a claim is always deliberate: assert that
`introspection_claims.keys` equals `%i[sub email email_verified first_name
last_name updated_at role]`. Target path: `test/models/user_test.rb`. House style: plain
Minitest, no framework, assert the invariant that would otherwise rot silently.

### Cost, and what caching would cost

One extra `SELECT` per introspection; already one query to resolve the role, so
the extra fields are free once the row is loaded. Introspection runs on every
request in every app.

An orphaned-user or deleted-user lookup misses the row entirely, which is the
cheap case. The moment you cache, the TTL is your revocation window, and it also
freezes the user's email and role.

**Do not log introspection response bodies.** They carry PII now, and
`config.filter_parameters` only covers params, not responses.

## Adding name fields

Devise creates no name columns — not `first_name`, `last_name`, `given_name`, or
`name`. This is ours to add.

- `first_name` and `last_name`, both `:string`, both `NOT NULL`.
- **Both columns are genuinely required.** The DB constraint is the backstop; a
  `presence: true` validation on the model is what turns a constraint violation
  into a form error instead of a 500.
- Two consequences that are chosen, not discovered: registration must ask for
  both names, and `POST /api/v1/users` must supply both.
- If the columns should be `NOT NULL` but the names optional, use
  `default: ""` instead of presence validations — that is Devise's own
  convention for `email`. The trade is that `""` becomes the sentinel for
  "missing", so `ORDER BY last_name` sorts the nameless to the top.
- Adding this to a populated table would need a backfill between `add_column`
  and the constraint. Auth Service has no users yet, so one `change` block is
  fine.

**Devise silently drops these params until you permit them.** No error, no
warning — the form just saves nothing, and the bug shows up as "the profile page
is broken". Permit `:first_name, :last_name` for both `:sign_up` and
`:account_update` in `configure_permitted_parameters`, guarded by
`if: :devise_controller?` in `ApplicationController`.

### Names keep their column names

`first_name` and `last_name` go out as-is, so the claims match the schema with no
translation layer to drift. The cost lands at the OIDC boundary:
`email_verified` and `updated_at` already match standard claim names, but these
two would need mapping to `given_name`/`family_name` in one place when
`doorkeeper-openid_connect` is enabled. One mapping there, once — not a column
rename now.

### Still no composed `name`

OIDC defines one, but building it is locale-dependent — family-name-first across
much of East Asia, family-given in Hungarian, a mononym elsewhere. Baking
"first last" into an authorization response imposes a presentation rule on every
client app. Auth Service reports the two parts; each client app composes what it
displays.

The same argument cuts against two columns: if nothing ever sorts by surname or
addresses a user formally, a single `name` column is simpler **and** more correct
across locales. Two columns were chosen because both parts are wanted as data —
worth revisiting if name stays display-only.
