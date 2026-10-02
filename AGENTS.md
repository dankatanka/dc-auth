# AGENTS.md

`docs/` is the authority; code is not documentation. Read before changing
behavior, update the doc in the same change. Full rationale:
`docs/coding-style.md`.

## The two rules

1. **Docs are the authority.** Read `docs/` before changing behavior; do not
   infer it from source. If a doc and the code disagree, that is a bug to report.
   A behavior change updates its doc in the same change.
2. **Comments explain why, never what.** No documentation, no obvious comments,
   no paragraphs, no links to `docs/`. A paragraph belongs in `docs/`. A
   deliberate shortcut gets a `ponytail:` comment naming its ceiling. Leave
   upstream gem/Rails comments alone unless the file is already ours.

## Before you finish

- Scan your added `#` lines. Each is one line of *why*, or nothing.
- Test helpers are public and at the top of the test file; no `private`. Tests
  live under `test/controllers`, one file per controller.
- Behavior changed? Its `docs/` file is updated in this change.

## Where to look

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
| How to write comments, what stays out of them | `docs/coding-style.md` |

Before touching `config/database.yml`, `config/cache.yml`, `bin/dev`, or the
frontend, read `docs/operations.md` — the traps are there.

## Commands

`bin/setup`, `bin/dev`, `bin/rails test`, `bin/ci` — see `docs/operations.md`
for what each does and for the known breakages.
