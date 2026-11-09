# Bootstrap

First-time setup of a **production** instance. Development needs none of this:
`bin/setup` seeds the `admin` application and two known-password users, and
`bin/dev` runs it (docs/operations.md).

Production must never seed. `db/seeds.rb` loads in every environment and creates
`administrator@example.com` / `password123` alongside the `admin` application —
and the application's secret is hashed at rest and never printed, so the seeded
`admin` app is unusable anyway. A production instance is bootstrapped in three
explicit steps instead: schema, `admin` application, first administrator.

## Order matters

`bin/docker-entrypoint` runs `db:prepare` whenever the container command is
`rails server`, and `db:prepare` **loads the seeds on a database it just
created**. If the first process to touch a blank database is a web pod, it
installs the `password123` accounts. Run the migration job first: once
`schema_migrations` exists, `db:prepare` only migrates and never seeds.

## 1. Schema

The database has to exist — create it in Postgres first. Then, from a one-off
pod or job:

```
bin/rails db:migrate
```

Not `db:prepare` and not `db:seed`; both seed a fresh database. On an empty one
`db:migrate` installs `db/schema.rb` and runs zero migrations — that silence is
expected (docs/operations.md).

## 2. The `admin` application

The admin application cannot be created through the API, because creating it
requires the scopes it grants. Create it out of band and **capture the secret
from the output**: `hash_application_secrets` means the plaintext exists only on
the instance that created the row.

```
kubectl exec -i deploy/dc-auth -- bin/rails runner - <<'RUBY'
app = Doorkeeper::Application.create!(
  name: "admin",
  redirect_uri: "urn:ietf:wg:oauth:2.0:oob",
  scopes: "admin:users admin:apps",
  confidential: true,
)
puts "uid=#{app.uid}"
puts "secret=#{app.plaintext_secret}"
RUBY
```

Store the `uid`/`secret` in a Secret. There is no rotate endpoint: a lost secret
means destroying and recreating the application, which takes its access tokens
and grants with it (docs/api.md). The `admin` application is machine-only — its
redirect URI is the out-of-band placeholder and it is never used for browser
login.

## 3. The first administrator

The admin API creates users **unconfirmed**, and `:confirmable` blocks login
until the emailed link is followed, so the first human is created out of band
too — confirmed, with a password you choose:

```
kubectl exec -i deploy/dc-auth -- bin/rails runner - <<'RUBY'
User.create!(
  email: "you@example.com",
  first_name: "Ada",
  last_name: "Admin",
  role: "administrator",
  password: "REPLACE_ME",
  password_confirmation: "REPLACE_ME",
  confirmed_at: Time.current,
)
RUBY
```

The values ride the exec channel, not argv, so they stay out of the pod's
process list — but they land in your shell history. For a real deployment run
the same code as a one-off Job with the password from a Secret.

## 4. Runtime environment

| Variable | Why |
|---|---|
| `RAILS_ENV=production` | the image sets it, but be explicit |
| `SECRET_KEY_BASE` | boot fails without it |
| `APP_HOST` | host in mailer links; boot fails without it |
| `DB_HOST`, `PG_USER`, `PG_PASSWORD` | the database |
| `RAILS_MASTER_KEY` | only if you edit credentials (SMTP) |
| `SOLID_QUEUE_IN_PUMA=1` | or run `bin/jobs` as its own Deployment. Without one or the other, jobs are enqueued and never performed |

SMTP is not configured (`config.action_mailer.smtp_settings` is commented out),
so until it is, users created through the API can never confirm. Wire it before
creating them (docs/operations.md).

The image serves Puma on `:3000` as uid 1000 (uid 1000 cannot bind `:80`).
`GET /up` is the health endpoint; it proves the app booted, not that Postgres is
reachable.

## 5. Client applications

Once the `admin` application exists, register every other client through the
admin API — it is the only route to scopes (docs/api.md). The dashboard is one:

```
token=$(curl -s -X POST https://auth.example.com/oauth/token \
  -d grant_type=client_credentials \
  -d client_id=<admin uid> -d client_secret=<admin secret> \
  -d scope="admin:apps" | jq -r .access_token)

curl -s -X POST https://auth.example.com/api/v1/applications \
  -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
  -d '{"application":{"name":"dashboard","redirect_uri":"https://dashboard.example.com/oauth/callback","scopes":"read:profile"}}'
```

The response carries the secret, and only that response does. Redirect URIs must
be https except on loopback (`localhost`, `127.0.0.1`, `::1`), where `http` is
allowed for local development. Endpoint shapes: docs/api.md.
