Generate all code artifacts for the project. Consult `.claude/skills/templ-htmx.md` and `.claude/skills/taskfile.md` for context on the generation pipeline.

Run the following from the `core/` directory in this order:

1. `templ generate` — regenerate all `*_templ.go` files from `*.templ` sources
2. `tailwindcss -i ./internal/web/ui/static/input.css -o ./internal/web/ui/static/styles.css --minify` — compile Tailwind CSS
3. `task db:generate` — run sqlc to regenerate Go DB models and queries

If `$ARGUMENTS` mentions "proto" or any `.proto` files were recently modified, also run `task proto:gen` from the repo root.

After all steps complete, run `go build ./...` from `core/` to verify no compilation errors. Report any errors clearly.
