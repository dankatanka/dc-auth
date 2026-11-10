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
    "role": "administrator",
    "scope": "openid profile email",
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
`profile_updated_at`. The payoff is that the OIDC provider (docs/decisions.md)
sends those claims with no mapping and no client app changes. The name claims
are the deliberate exception (below).

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

## The OIDC surface

`doorkeeper-openid_connect` adds `GET /.well-known/openid-configuration`,
`GET /oauth/discovery/keys`, and `GET|POST /oauth/userinfo`, and puts an
`id_token` in the token response whenever the grant carries the `openid` scope.

It is the same user data over a different wire, so it must not become a second
whitelist:

- **Values come from `User#introspection_claims`** — the same method, so the two
  surfaces cannot drift. Only the names differ: `first_name`/`last_name` go out
  as `given_name`/`family_name`, and `sub` is the same `id.to_s`. A test asserts
  the OIDC claim names are exactly the introspection keys with those two
  renames, minus `sub` (which OIDC supplies itself).
- **Claims follow the granted scopes**: `email` and `email_verified` by `email`,
  the rest by `profile`; `openid` alone yields just `sub`. Off-the-shelf RP
  libraries ask for `openid profile email`, which is why all three are
  configured scopes and why existing applications were granted them; the
  migration that grants them also drops the retired `read:profile`
  (docs/decisions.md).
- **The ID token is an identity assertion, not an authorization one.** It is
  signed RS256 with the key at `OIDC_SIGNING_KEY_PATH` and published at
  `/oauth/discovery/keys`; no JWT access token is issued, so every authorization
  decision still goes through introspection.
- **The issuer is one fixed value, not the request host.** Discovery and the ID
  token both report `#{scheme}://APP_HOST`. The ID token is built during the
  token exchange, where the gem hands the issuer block no request, so a
  request-derived issuer would be advertised in discovery and never signed into
  the token — the mismatch that makes an RP reject every ID token. A fixed value
  also keeps a forged `Host` header out of the issuer.

The signing key is the one new secret, and it is a single key with no rotation
window: rotating it invalidates every client's cached JWKS until they refetch.
That is the deliberate ceiling (docs/bootstrap.md).

### Session parameters an RP will send

Four of these are configured rather than left at the gem's default, because the
default is either a `500` or a security hole:

- **`nonce`** rides through the consent form. Doorkeeper's stock
  `authorizations/new` view submits no `nonce`, so the grant and the ID token
  lose it and a conforming RP rejects the token; we own that one view to add the
  hidden field to both forms. The test submits the rendered form rather than
  re-POSTing the request, because the latter hides exactly this bug.
- **`prompt=login`** signs the user out and sends them to the sign-in form, with
  the consent screen stored as the return-to. Without the callback the gem
  raises instead.
- **`prompt=select_account`** answers `account_selection_required`. There is no
  account picker — one session is one user — and the gem's default raises a
  configuration error, which is a `500` for a parameter an RP is entitled to
  send.
- **`max_age`** is measured against *this session's* sign-in time, stamped into
  the Rack session by Warden at sign-in. The gem's fallback is the user's most
  recent login on any device, so a stale session could satisfy an RP's freshness
  requirement by piggy-backing on a fresh login elsewhere. The `auth_time`
  *claim* still reports the last login, which is what it means at issuance.

`offline_access` is deliberately **not** a configured scope. `use_refresh_token`
is unconditional, so it would be a no-op, and OIDC Core §11 requires the
authorization server to ignore it unless `prompt=consent` is present —
advertising it would claim an implementation that is not there. A client that
asks for it gets `invalid_scope`; add the scope when a real one does.

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

`first_name` and `last_name` go out as-is over introspection, so the claims
match the schema with no translation layer to drift. The cost lands at the OIDC
boundary: `email_verified` and `updated_at` already match standard claim names,
but these two are mapped to `given_name`/`family_name` in the OIDC initializer.
One mapping there, once — not a column rename.

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
