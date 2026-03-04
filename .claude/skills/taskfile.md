---
name: taskfile
description: Run dev, database, code generation, and infrastructure tasks via the Taskfile
---

# Taskfile Skill

All project operations are driven by `task` (Taskfile v3). Run `task --list` to see all tasks. Requires a `.env` file in the repo root for infrastructure tasks.

**Runner**: `task <task-name>` from the repo root, unless a task specifies `dir:`.

## Quick Start

```bash
task dev:web         # BFF (templ watch + tailwind watch + air hot reload)
task dev:server      # Core API with hot reload
task dev             # Both server + web together
task db:setup        # Start DB, run migrations, generate sqlc models
task db:generate     # Regenerate sqlc models after SQL changes
```

## Task Groups

### Development
```bash
task dev             # Run server + web (parallel, hot reload)
task dev:server      # Core API only (Air, .air.server.toml)
task dev:web         # BFF only (templ watch + tailwind watch + Air)
task dev:worker      # Background build worker (Air, .air.worker.toml)
task dev:cli -- <args>   # Build and run the plat CLI from source
```
All `dev:*` tasks run from the `core/` directory (Taskfile sets `dir: core`).

### Database
```bash
task db:up                          # Start local PostgreSQL (docker compose)
task db:down                        # Stop local PostgreSQL
task db:migrate                     # Apply all pending migrations
task db:migrate-down                # Roll back the last migration (down 1)
task db:create-migration NAME=xxx   # Scaffold a new migration (snake_case name)
task db:generate                    # Run sqlc to regenerate Go models and queries
task db:setup                       # Full setup: up → wait 5s → migrate → generate
task db:login                       # Open psql shell in the running container
```
Migrations live in `core/migrations/`. Generated code goes to `core/internal/db/`.

### Code Generation
```bash
task db:generate     # sqlc: regenerates Go from SQL queries (run from core/)
task proto:gen       # buf generate: ConnectRPC Go code from .proto files (run from proto/)
task proto:lint      # buf lint: validate Protobuf contracts
```

### Infrastructure — Packer (Image Builds)
```bash
task packer:hz           # Build all Hetzner images (K3s + NAT)
task packer:hz:k3s       # Build only Hetzner K3s image
task packer:hz:nat       # Build only Hetzner NAT gateway image
task packer:do           # Build all DigitalOcean images
task packer:do:k3s       # Build only DO K3s image
task packer:do:nat       # Build only DO NAT gateway image
```
Requires `HCLOUD_TOKEN` (and `DOCLOUD_TOKEN` for DO) in `.env`.

### Infrastructure — Terraform (Cluster Provisioning)
```bash
task hz:plan             # terraform plan — Hetzner Ashburn (dev)
task hz:apply            # terraform apply — Hetzner Ashburn (dev)
task hz:destroy          # terraform destroy — Hetzner Ashburn (dev)
task hz:output           # Show Hetzner terraform outputs

task do:plan             # terraform plan — DigitalOcean NYC3 (dev)
task do:apply            # terraform apply — DigitalOcean NYC3 (dev)
task do:destroy          # terraform destroy — DigitalOcean NYC3 (dev)
task do:output           # Show DigitalOcean terraform outputs
```
Requires `HCLOUD_TOKEN`, `DOCLOUD_TOKEN`, `GIT_REPO_URL`, and GCS credentials in `.env`.
State is stored in GCS. Backend is reconfigured on every `init`.

### Cluster Operations
```bash
task cluster:seal TENANT=<ns> NAME=<secret> KEY=<k> VAL=<v>
```
SSHs into the control plane, runs `kubectl` + `kubeseal` remotely, saves the sealed YAML locally to `tenants/<TENANT>/<NAME>-secret.yaml`. Installs `kubeseal` on the remote if missing.

## Decision Tree

- **Start developing the web frontend** → `task dev:web`
- **Start developing the API** → `task dev:server`
- **Everything at once** → `task dev`
- **After editing `.templ` files** → `templ generate` (watcher handles it in `dev:web`)
- **After editing SQL queries** → `task db:generate`
- **After editing `.proto` files** → `task proto:gen`
- **Need a new migration** → `task db:create-migration NAME=xxx` then edit the files then `task db:migrate`
- **Provision new infrastructure** → `task hz:plan` → review → `task hz:apply`
- **Seal a new secret for a tenant** → `task cluster:seal TENANT=... NAME=... KEY=... VAL=...`

## Anti-Patterns

- **Running `task dev:*` from outside the repo root**: Taskfile sets `dir: core` for dev tasks internally — always invoke `task` from the repo root.
- **Running Terraform tasks without `.env`**: All infra tasks require cloud tokens. Missing vars cause silent failures or wrong resource targeting.
- **Running `task hz:apply` before `task hz:plan`**: Always plan first and review the diff. Apply uses `-auto-approve`.
- **Running `task db:generate` before migrating**: sqlc generates from the live schema. Always migrate first or generated code will be stale.
- **Forgetting `NAME=` for `db:create-migration`**: The task requires the `NAME` var — it will error without it.
- **Running `task dev` and `task dev:web` simultaneously**: They both start the BFF. Pick one.
