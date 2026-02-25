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
- **Infrastructure as Code:** Terraform (`infrastructure/terraform/providers/`).
- **Base Images:** Packer (`infrastructure/packer/`) for hardened Ubuntu + k3s + gVisor.
- **Task Runner:** `go-task` (Taskfile) is used to wrap complex CLI operations.
- **Kubernetes:** k3s cluster with multi-node support.
- **Platform Stack:** 
    - **Database:** PostgreSQL (managed by `sqlc` & `golang-migrate` locally, and CloudNativePG in-cluster).
    - **API Framework:** ConnectRPC (Go) generated from Protobufs (`proto/`).
    - **Continuous Deployment:** ArgoCD.
    - **Serverless/Messaging:** Knative Serving & Eventing, NATS.
    - **Security:** Cilium, KubeArmor, & Kyverno for networking and runtime security.
    - **Observability:** VictoriaMetrics, Loki, Grafana, and Fluent Bit.

---

## Before You Start (Preflight)
1. Ensure your `.env` file is populated with required tokens (`HCLOUD_TOKEN`, `DOCLOUD_TOKEN`, etc.).
2. Verify local tooling:
   - `task --version`
   - `terraform --version`
   - `kubectl version --client`
   - `packer --version`
   - `buf --version`
   - `docker --version`
   - `go version`
   - `npm --version`
3. Confirm you have the Google Cloud SDK installed if managing the Terraform remote state (GCS).
4. Verify the `keys/` directory contains the necessary service account JSON for the Terraform backend.

---

## Experimental Workflows

### A. Build Base Images (Packer)
Packer images include k3s and gVisor pre-installed.
- Build for Hetzner K3s: `task packer:hz:k3s`
- Build for Hetzner NAT Gateway: `task packer:hz:nat`
- Build for DigitalOcean K3s: `task packer:do:k3s`
- Build for DigitalOcean NAT Gateway: `task packer:do:nat`

### B. Development & Code Generation
We use ConnectRPC and `buf` for our APIs, along with local live-reload via `air`.

- **Proto Generation:** `task proto:gen`
- **Proto Linting:** `task proto:lint`
- **Run API (live-reload):** `task dev:api`
- **Run Worker (live-reload):** `task dev:worker`
- **Run Web Frontend:** `task web:dev`

### C. Infrastructure (Terraform)
We use Taskfile wrappers to manage provider-specific state and variables.
- **Hetzner (Ashburn/Dev):**
  - Plan: `task hz:plan`
  - Apply: `task hz:apply`
  - Destroy: `task hz:destroy`
  - Kubeconfig: `task hz:kubeconfig`
  - Output: `task hz:output`
- **DigitalOcean (NYC3/Dev):**
  - Plan: `task do:plan`
  - Apply: `task do:apply`
  - Destroy: `task do:destroy`
  - Kubeconfig: `task do:kubeconfig`
  - Output: `task do:output`

### D. Platform Components (Kubernetes)
Platform components are automatically deployed via **ArgoCD**.
The root application configuration and bootstrap manifests are applied automatically by Terraform during cluster creation (`infrastructure/terraform/modules/k3s_node/bootstrap/`).
Subsequent platform updates should be made in `infrastructure/kubernetes/manifests`, which ArgoCD will sync automatically.

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
- **Code Generation:** `task db:generate`
- **Migrations:**
  - Create: `task db:create-migration NAME=my_new_table`
  - Apply: `task db:migrate`
  - Rollback: `task db:migrate-down`
- **Access:** `task db:login`

---

## API & Development
The API is versioned under `/v1` and uses ConnectRPC.
- **Base URL:** `http://localhost:8080/v1`
- **Auth:** WorkOS integration is used for authentication. Protected routes require a valid session or Bearer token.
- **Protobuf Contracts:** API interfaces and models are strictly typed via definitions in the `proto/` directory.

---

## Backups & Restore

### Cluster Backups (etcd)
- S3-compatible storage is used for etcd snapshots (defined in Terraform variables).
- Configuration is handled via k3s flags on the control plane.

### Database Backups (CNPG)
- The CloudNativePG operator handles backups for the Postgres cluster.
- Check backup status: `kubectl get backup -n <namespace>`
- Manifests in `infrastructure/kubernetes/manifests` define the backup secret and cluster configuration.

---

## Debugging & Learning Notes

1. **Check Node Status:** `kubectl get nodes -o wide`
2. **Check Platform Health:**
   - CNPG: `kubectl get clusters -n <ns>`
   - Knative: `kubectl get ksvc -A`
   - NATS: `kubectl get pods -l app.kubernetes.io/name=nats`
   - ArgoCD: `kubectl get pods -n argocd`
3. **Logs:**
   - API Server: `kubectl logs -l app=platform-api`
   - Ingress: `kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx`
4. **Terraform State:** If a `task` command fails, verify the `-backend-config` variables in the Taskfile match your environment.

---

## Learning Log (Revision History)