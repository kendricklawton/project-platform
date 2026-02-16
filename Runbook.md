# Runbook (Operational Notes) 📝

This document tracks our experiments in provisioning and operating the `project-platform` infrastructure. It serves as a guide for our learning journey, documenting the steps we've discovered so far.

**Note:** This is a work in progress and not meant for stable environments. We are learning by doing!

IMPORTANT
- Never commit secrets, private keys, or service account JSON files to the repository.
- Use the `.env` file (excluded from git) for local development and Taskfile variables.
- Replace placeholders with values stored in your local secret manager or environment files.
- These commands are for experimental use—run them with caution as we are still figuring things out!

---

## Environment & Assumptions
- **Cloud Providers:** Hetzner Cloud (`hz`) and DigitalOcean (`do`).
- **Infrastructure as Code:** Terraform (`infra/terraform/providers/`).
- **Base Images:** Packer (`infra/packer/`) for hardened Ubuntu + k3s + gVisor.
- **Task Runner:** `go-task` (Taskfile) is used to wrap complex CLI operations.
- **Kubernetes:** k3s cluster with multi-node support.
- **Platform Stack:** 
    - **Database:** CloudNativePG (CNPG) for in-cluster Postgres.
    - **Serverless:** Knative Serving & Eventing.
    - **Messaging:** NATS.
    - **Security:** KubeArmor & Kyverno for policy enforcement and runtime security.
    - **Observability:** VictoriaMetrics, Loki, Grafana, and Fluent Bit.
    - **GitOps:** ArgoCD for declarative application management.

---

## Before You Start (Preflight)
1. Ensure your `.env` file is populated with required tokens (`HCLOUD_TOKEN`, `DOCLOUD_TOKEN`, etc.).
2. Verify local tooling:
   - `task --version`
   - `terraform --version`
   - `kubectl version --client`
   - `packer --version`
   - `ko version` (optional)
   - `docker --version`
3. Confirm you have the Google Cloud SDK installed if managing the Terraform remote state (GCS).
4. Verify the `keys/` directory contains the necessary service account JSON for the Terraform backend.

---

## Experimental Workflows

### A. Build Base Images (Packer)
Packer images include k3s and gVisor pre-installed.
- Build for Hetzner: `task packer:hz`
- Build for DigitalOcean: `task packer:do`
- Build all: `task packer:all`

### B. Build Application Images (ko or Docker)
We offer a choice between `ko` (optimized Go builds) and standard Docker.

**Option 1: Build with ko (Recommended for Go DX)**
- Build API: `task build:ko:api`
- Build CLI: `task build:ko:cli`
- By default, these build to `ko.local`. For remote registries, set `KO_DOCKER_REPO` in your `.env`.

**Option 2: Build with Docker**
- Build API: `task build:docker:api`
- Build CLI: `task build:docker:cli`

### C. Infrastructure (Terraform)
We use Taskfile wrappers to manage provider-specific state and variables.
- **Hetzner (Ashburn/Dev):**
  - Plan: `task hz:plan`
  - Apply: `task hz:apply`
  - Kubeconfig: `task hz:kubeconfig`
- **DigitalOcean (NYC3/Dev):**
  - Plan: `task do:plan`
  - Apply: `task do:apply`

### D. Platform Components (Kubernetes)
The platform manifests are located in `infra/platform/manifests`.
- These are typically applied via the infrastructure pipeline, but can be applied manually:
  ```bash
  kubectl apply -f infra/platform/manifests/
  ```
- **Security Check:** Verify Kyverno and KubeArmor policies are active:
  ```bash
  kubectl get clusterpolicy
  kubectl get kubearmorpolicy -A
  ```

---

## Local Database Management
For local development, use Docker Compose and Taskfile helpers.

- **Initial Setup:** `task db:setup` (Up, Migrate, Generate SQLC)
- **Start/Stop:** `task db:up` / `task db:down`
- **Migrations:**
  - Create: `task db:create-migration NAME=my_new_table`
  - Apply: `task db:migrate`
  - Rollback: `task db:migrate-down`
- **Access:** `task db:login`

---

## API & Development
The API is versioned under `/v1`.
- **Base URL:** `http://localhost:8080/v1`
- **Auth:** All protected routes require a Bearer token.
- **Trailing Slashes:** The API uses `middleware.CleanPath`, so `/projects/` and `/projects` are treated identically.
- **Errors:** All errors are returned as JSON: `{"error": "message"}`.

---

## Backups & Restore

### Cluster Backups (etcd)
- S3-compatible storage is used for etcd snapshots (defined in Terraform variables).
- Configuration is handled via k3s flags on the control plane.

### Database Backups (CNPG)
- The CloudNativePG operator handles backups for the Postgres cluster.
- Check backup status: `kubectl get backup -n <namespace>`
- Manifests `311` and `312` in `infra/platform/manifests` define the backup secret and cluster configuration.

---

## Debugging & Learning Notes

1. **Check Node Status:** `kubectl get nodes -o wide`
2. **Check Platform Health:**
   - CNPG: `kubectl get clusters -n <ns>`
   - Knative: `kubectl get ksvc -A`
   - NATS: `kubectl get pods -l app.kubernetes.io/name=nats`
3. **Logs:**
   - API Server: `kubectl logs -l app=platform-api`
   - Ingress: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`
4. **Terraform State:** If a `task` command fails, verify the `-backend-config` variables in the Taskfile match your environment.

---

## Learning Log (Revision History)
