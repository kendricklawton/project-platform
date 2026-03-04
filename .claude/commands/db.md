Handle database operations based on `$ARGUMENTS`. Consult `.claude/skills/taskfile.md` for full task reference.

Handle database operations based on `$ARGUMENTS`:

- `up` — run `task db:up` to start the local PostgreSQL container
- `down` — run `task db:down` to stop it
- `migrate` — run `task db:migrate` to apply all pending migrations
- `rollback` — run `task db:migrate-down` to roll back the last migration
- `generate` — run `task db:generate` to regenerate sqlc models and queries
- `setup` — run `task db:setup` (starts DB, waits, migrates, generates)
- `login` — run `task db:login` to open a psql shell
- no args — print the available options listed above

All task commands are run from the repo root.
