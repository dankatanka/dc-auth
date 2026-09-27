# Roles

Roles are a single string column on `users`. No gem, no join tables, no policy
DSL. Auth Service reports the name; each client app maps the name to its own
rules.

- Column `role`, `:string`, `NOT NULL`, `default: "user"`.
- Values constrained in the database by a check constraint —
  `role IN ('user', 'staff', 'admin')` — and in Ruby by a Rails `enum` with
  `validate: true`.
- The three roles are `user`, `staff`, `admin`.
- `User.roles.keys` is the canonical role list — there is no separate `ROLES`
  constant to drift out of sync with the enum.

Role changes take effect on the **next request**, because every request is
introspected. No waiting for token expiry.

## Enum syntax, and one trap

Rails 8 **removed** the keyword form. The positional form is required:
`enum :role, ...` works, `enum role: [...]` raises.

Map names to their own string values — `enum :role, { user: "user", staff:
"staff", admin: "admin" }`, or the compact
`%i[user staff admin].index_with(&:to_s)`. **Never use the plain array form on a
string column.** Measured on Rails 8.1.3.1:

| Definition (string column) | `role` reads | stored in DB | `admin?` |
|---|---|---|---|
| `enum :role, %i[user staff admin]` | `"admin"` | `"2"` | `false` |
| `enum :role, { admin: "admin" }` | `"admin"` | `"admin"` | `true` |
| `enum :role, %i[user staff admin].index_with(&:to_s)` | `"admin"` | `"admin"` | `true` |

The array form maps names to the **integers** 0/1/2 and then serializes them
into the string column. Ruby reads back `"admin"` so nothing looks wrong in the
console, but the database holds `"2"`, the predicate methods are `false`, and the
check constraint rejects the row. It is only correct on an integer column.

`validate: true` is doing two jobs, and both are needed. Without it, assigning an
unknown role raises `ArgumentError: 'admn' is not a valid role`, which escapes a
controller as a 500. With it, the same assignment produces `valid? == false` and
a normal form error. It also makes `role` **required** — `nil` fails validation
too, which is what a value every authorization decision depends on deserves.

**Integer backing is the alternative:** `enum :role, { user: 0, staff: 1, admin:
2 }`, where the array form becomes correct. You pay in readability — the check
constraint turns into `role IN (0, 1, 2)`, so a row in psql no longer says what
it means, and the introspection claim needs the label rather than the stored
value. String values keep the database self-describing and match what client
apps receive.

The enum also generates scopes — `User.user`, `User.staff`, `User.admin`.
`User.user` reads badly in queries; pass `scopes: false` to keep them explicit.

The check constraint is a plain constraint rather than a Postgres `ENUM` type on
purpose: adding a role is then an ordinary migration, not an `ALTER TYPE` that
cannot be reversed.

## The contract

Auth Service owns the **set of role names**. Each client app owns the **policy**
for those names. A downstream app receives `role: "staff"` and decides for itself
what a staff member may do there. It never asks Auth Service what a role means.

Consequences to accept:

- **Role names are a public API.** Every client app hardcodes them. Renaming or
  removing a role is a breaking change across N apps and needs a deprecation
  period. Adding a role is safe.
- **No per-app limits.** Every app holding an admin's token carries the admin's
  full power; one app cannot be distinguished from another. That is the intended
  trade — one trust level for internal apps. Scopes are the upgrade path if it
  stops being true.
- **No central policy view.** "What can a staff user do?" is answerable only by
  grepping the client apps. The audit log (docs/roadmap.md, Phase 3) is the
  mitigation.
- **Fail closed, both directions.** Auth Service validates `role` against
  `User.roles.keys` plus the DB check constraint, so a typo cannot mint an
  unknown role. Every client app's role map must default-deny on an unrecognised
  role name rather than fall through to its own logic.
