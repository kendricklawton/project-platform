Create a new database migration.

`$ARGUMENTS` should be the migration name in snake_case (e.g. `create_users` or `add_api_key_to_projects`).

If no argument is provided, ask the user for the migration name before proceeding.

Steps:
1. Run `task db:create-migration NAME=$ARGUMENTS` from the repo root to scaffold the up/down SQL files in `core/migrations/`
2. Show the user the paths of the two generated files
3. Wait for the user to fill in the SQL before running `task db:migrate`

Do not auto-run the migration — the user must populate the SQL files first.
