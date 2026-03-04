---
name: plat-cli
description: Deploy and manage services on the platform using the plat CLI
---

# plat CLI Skill

The `plat` CLI deploys and manages Go/Rust/Zig services on the platform. Config lives at `~/.plat/config.json`. Token is read from config or `PLAT_TOKEN` env var.

**During development**, run via: `task dev:cli -- <args>` from the repo root (builds and runs the CLI from source).
**Installed binary**: `plat <command>`

## Quick Start

```bash
plat auth login          # OAuth via browser — saves token to ~/.plat/config.json
plat init                # auto-detect lang (go.mod / Cargo.toml) and write plat.toml
plat deploy              # deploy from current directory (requires plat.toml)
plat status              # show all services and their state
plat logs                # stream live logs
```

## Commands

### Auth
```bash
plat auth login          # browser OAuth flow — opens browser, waits for callback
plat auth logout         # clear saved token
plat auth status         # show current auth state
```

### Project Init
```bash
plat init                # auto-detect go or rust from go.mod / Cargo.toml
plat init --lang go      # force Go
plat init --lang rust    # force Rust
```
Creates `plat.toml` in the current directory. Will not overwrite an existing one.

**plat.toml shape:**
```toml
[app]
name = "my-service"
lang = "go"

[build]
command = "go build -o bin/app ."

[run]
command = "./bin/app"
```

### Deploy
```bash
plat deploy                      # deploy current branch
plat deploy --branch feat/xyz    # deploy a specific branch
plat deploy --wait               # block until deploy completes
```
Requires `plat.toml` in the current directory. If missing, run `plat init` first.

### Status
```bash
plat status                      # list all services (name, lang, status, revision, url)
plat status --service my-svc     # show a specific service
```

### Logs
```bash
plat logs                        # stream all logs
plat logs --service my-svc       # stream logs for one service
plat logs --since 1h             # show logs from 1 hour ago (e.g. 30m, 2h)
```

### Rollback
```bash
plat rollback                    # roll back to previous revision (prompts for confirmation)
plat rollback --to v12           # roll back to a specific revision
```

### Secrets
```bash
plat secret set KEY VALUE        # set a secret (stored encrypted in cluster)
plat secret list                 # list secret keys (values never shown)
plat secret delete KEY           # delete a secret (prompts for confirmation)
```

### Version
```bash
plat version                     # print CLI version
```

## Global Flags
```bash
--token <token>                  # override PLAT_TOKEN / saved config token
--config <path>                  # use a custom config file path
```

## Decision Tree

- **First time setup** → `plat auth login` then `plat init`
- **Deploy a service** → ensure `plat.toml` exists, then `plat deploy`
- **Check what's running** → `plat status`
- **Debug a failing service** → `plat logs --service <name>`
- **Undo a bad deploy** → `plat rollback` or `plat rollback --to <revision>`
- **Pass env vars to a service** → `plat secret set KEY VALUE`
- **Auth broken / token expired** → `plat auth logout` then `plat auth login`

## Anti-Patterns

- **Running `plat deploy` without `plat.toml`**: Will fail immediately. Always run `plat init` first in a new project directory.
- **Running from the wrong directory**: Commands like `deploy`, `init`, and `logs` are directory-aware. Must be run from the project root where `plat.toml` lives.
- **Hardcoding tokens**: Use `PLAT_TOKEN` env var or the saved config — never pass `--token` in scripts committed to git.
- **Not using `--wait` in CI**: Without `--wait`, deploy returns immediately after triggering. Use `--wait` if you need to gate on deploy success.
- **Forgetting `plat auth login` before other commands**: All commands except `version` check for a valid token and exit 1 if missing.
