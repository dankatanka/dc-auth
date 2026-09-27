# AGENTS.md

## 1. Do not use code as documentation. Use `docs/` for finding.

Documentation lives in `docs/`. Code is not the documentation.

- **Read `docs/` before changing behavior.** Do not infer how something works or
  why it is that way from the source. Each doc is the authority for its topic;
  if a doc and the code disagree, that is a bug to report, not something to
  quietly work around.
- **Code comments carry intent, not explanation.** Only non-obvious intent and
  known ceilings belong in a comment (`# ponytail: global lock, ...`). If you are
  writing a paragraph in a comment, it belongs in `docs/`.
- **Documentation is prose first.** Keep excerpts short and point at the file
  that holds the real thing. Never paste a copy of existing code into `docs/` —
  it drifts, and then the doc is worse than nothing.
- **When you change behavior, update the doc in the same change.** Docs are
  updated with the code, never "later".

### Where to look

| Question | Read |
|---|---|
| What is this service, what does it refuse to be | `README.md`, `docs/architecture.md` |
| How are tokens validated, what is in the response | `docs/validation.md` |
| What does a role mean, how is it stored | `docs/roles.md` |
| What must revoke, and when | `docs/revocation.md` |
| What endpoints exist, how does the admin app authenticate | `docs/api.md` |
| How do I run it, why is the database set up this way, what is broken | `docs/operations.md` |
| Which versions, why this gem and not that one | `docs/stack.md` |
| What is built, what is next | `docs/roadmap.md` |
| Why not JWT / Pundit / a policy DSL | `docs/decisions.md` |

### Non-obvious state worth knowing before you touch anything

- **One database per environment.** Solid Cache and Solid Queue tables are
  ordinary migrations in `db/migrate` and ride the primary connection pool.
  Re-adding `cache:`/`queue:` to `config/database.yml`, a `database:` key to
  `config/cache.yml`, or `config.solid_queue.connects_to` breaks that.
- **There is no asset pipeline.** Vite owns the frontend; yarn is the package
  manager. `stylesheet_link_tag`, `javascript_importmap_tags`, and
  `stale_when_importmap_changes` do not exist here.
- **`bin/dev` pins `-p 3000` on purpose.** Foreman would otherwise hand Rails
  `PORT=5000`, which `config/puma.rb` would silently accept.
- **`DB_HOST` switches the database connection.** `.devcontainer/devcontainer.json`
  sets it to `postgres` to reach the `postgres:18` sidecar; it is unset locally,
  where the pg gem uses the domain socket. That is why `config/database.yml` is
  ERB and why the single-database assertion parses it through
  `ActiveSupport::ConfigurationFile` rather than raw YAML.
- **Ruby is 4.0.7.** `.ruby-version`, the `Dockerfile` ARG, and `Gemfile.lock`
  agree; keep them that way.

## 2. Comments explain why, never what. No documentation in comments.

Rule 1 says where documentation goes. This says what is left in a comment.
Applies to code and to config — Ruby, YAML, Dockerfile, JSON, ERB alike.

- **No documentation in comments.** If a comment explains how something works,
  how to use it, or what the design is, it belongs in `docs/`. A comment is not
  a place to document behavior, options, or architecture.
- **No obvious comments.** If the code says it, do not say it again. `# Install
  gems` over `bundle install`, `# the port` over `port: 3000`, `# Configure the
  database` over `database:` — all noise.
- **Why, not what.** A comment earns its place by recording what the code cannot
  express: a constraint, a trap, a trade-off. State the reason, not the
  mechanics.
- **No links into `docs/`.** A comment states its own reason; it never cites a
  doc path. Docs are removable, and a stale path in code outlives them.
- **Upstream boilerplate is not ours to churn.** Comments shipped by Rails or a
  gem, in a file we have not otherwise rewritten, stay as they are. In a file we
  own or have rewritten they are fair game. A stale upstream comment that has
  become wrong is an exception: fix it.

```ruby
# yes: the constraint that is invisible from here
# postgres:18 keeps PGDATA in a versioned subdirectory; at the old mount path
# the container exits.

# no: restates the line, explains nothing
# Set up the database connection.
```

## Commands

`bin/setup`, `bin/dev`, `bin/rails test`, `bin/ci` — see `docs/operations.md`
for what each does and for the known breakages.
