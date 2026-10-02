# Coding style

Why the house rules in `AGENTS.md` exist. The checklist there is short on
purpose; the reasoning lives here.

## Code is not documentation

`docs/` is the authority for how this service works and why. The source is not a
backup doc, and an agent — or a person — must not reconstruct behavior by reading
it. So:

- Read `docs/` before changing behavior. Each doc owns its topic.
- If a doc and the code disagree, that is a bug to report, not something to
  quietly route around. Fix the disagreement, whichever side is wrong.
- Documentation is prose first. Keep excerpts short and point at the file that
  holds the real thing. Never paste a copy of existing code into `docs/` — the
  copy drifts and then the doc is worse than nothing.
- A behavior change updates its doc in the same change, never "later". Later is
  how docs become lies.

The payoff is a single place to look, and comments that do not rot into a second,
unauthoritative description of the system.

## Comments explain why, never what

A comment earns its place by recording what the code cannot express: a
constraint, a trap, a trade-off. Everything else is noise or documentation.

- **No documentation.** If a comment explains how something works, how to use
  it, or what the design is, it belongs in `docs/`. A comment is not a place to
  document behavior, options, or architecture.
- **No obvious comments.** If the code says it, do not say it again. `# Install
  gems` over `bundle install`, `# the port` over `port: 3000`, `# Configure the
  database` over `database:` — all noise.
- **No paragraphs.** If you are writing more than a line or two, it belongs in
  `docs/`. The length is the tell.
- **No links into `docs/`.** A comment states its own reason; it never cites a
  doc path. Docs are removable, and a stale path in code outlives them.
- **Upstream boilerplate is not ours to churn.** Comments shipped by Rails or a
  gem, in a file we have not otherwise rewritten, stay as they are. In a file we
  own or have rewritten they are fair game. A stale upstream comment that has
  become wrong is the exception: fix it.
- **Deliberate shortcuts get a `ponytail:` comment** naming the ceiling and the
  upgrade path, so a simple line reads as intent rather than ignorance.

```ruby
# yes: the constraint that is invisible from here
# postgres:18 keeps PGDATA in a versioned subdirectory; at the old mount path
# the container exits.

# no: restates the line, explains nothing
# Set up the database connection.
```

## The checklist, and what it is for

`AGENTS.md` states the rules as a pre-finish checklist because that is the form
that gets followed. The rules are prose here for people; the checklist there is
for the moment a change is about to be written. When the two disagree, this file
is the authority.

The rest of the project's non-obvious traps — the single database, the absent
asset pipeline, `bin/dev`'s pinned port, `DB_HOST`, the Ruby version — are in
`docs/operations.md`. `AGENTS.md` routes there rather than repeating them.
