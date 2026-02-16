# Runbook

This runbook is the single canonical source for provisioning, operating, and recovering the `project-platform` infrastructure. It is intentionally concise and action-oriented so on-call engineers and maintainers can quickly find and execute the right steps.

IMPORTANT
- Never commit secrets, private keys, or service account JSON files to the repository.
- Replace placeholders (e.g., `<PROJECT_ID>`, `<TFSTATE_BUCKET>`, `<MAINTAINER_CONTACT>`, `<NODE_PUBLIC_IP>`, `<DB_CONTAINER_NAME>`, `<DB_USER>`, `<DB_NAME>`) with values stored in your secret manager or in environment-specific variable files that are excluded from source control.
- Keep all high-risk commands in a reviewed PR or runbook playbook before executing in production.

---

## Environment & Assumptions
- Cloud provider: Google Cloud Platform (GCP) — adjust if different.
- Infrastructure as code: Terraform (`infra/`).
- Base images: Packer (`infra/packer/`) — optional.
- Platform manifests: Kubernetes manifests under `infra/platform` (no Helm).
- Kubernetes: k3s cluster deployed via Terraform and plain manifests.
- Ingress: ingress-nginx manifests or cloud Load Balancer managed by Terraform/provider.
- Remote state: GCS bucket — `<TFSTATE_BUCKET>`.
- Etcd snapshots/backups: stored in `<ETCD_SNAP_BUCKET>` (S3/GCS compatible).
- Database: PostgreSQL, typically run locally via Docker Compose (`db` service in `docker-compose.yml`).
- CI: protected variables for secrets (do not store secrets in repo).

---

## Before You Start (Preflight)
1. Authenticate and set target project:
   - `gcloud auth login`
   - `gcloud config set project <PROJECT_ID>`
2. Verify local tooling and versions:
   - `terraform --version`
   - `kubectl version --client`
   - `packer --version` (if used)
   - `docker --version` (for local database and other containers)
   - `task --version` (for Taskfile shortcuts)
3. Confirm kubeconfig/context:
   - `kubectl config current-context`
4. Confirm Terraform remote state and CI secrets are in place and protected.
5. Announce maintenance to on-call and stakeholders; record maintenance window.

---

## SSH / Node Access Pattern
We assume direct node access as needed (provider-assigned IPs or provider tooling). Do NOT commit private keys.

- Direct SSH example:
  ```bash
  ssh <ADMIN_USER>@<NODE_PUBLIC_IP>
  ```
- GCP example (preferred for GCP-managed keys / IAM integration):
  ```bash
  gcloud compute ssh <INSTANCE_NAME> --project=<PROJECT_ID> --zone=<ZONE>
  ```
- Use provider tooling when available to avoid managing long-lived keys.
- Key management:
  - Use unique SSH keys per account/environment.
  - Upload only public keys to provider IAM/compute consoles.
  - Never store private keys or service-account JSON in the repo.

---

## Provisioning & Deployments

### A. Build Images (optional)
- Build Packer images when you need baked-in binaries:
  ```bash
  cd infra/packer
  packer init .
  packer build ubuntu-k3s.pkr.hcl
  ```
- Record snapshot/image IDs in a secrets store or external tracker (NOT in git).

### B. Terraform (Infrastructure)
- Keep per-environment variable files out of source control (e.g., `dev.tfvars`).
- Standard workflow:
  ```bash
  cd infra
  terraform init
  terraform validate
  terraform plan -var-file=dev.tfvars
  ```
- Review plan in PR and get approver sign-off.
- Apply with approver present:
  ```bash
  terraform apply -var-file=dev.tfvars
  ```

### C. Kubernetes (manifests)
- Deploy using manifests in `infra/platform` or via CI pipeline that applies them.
- Apply manifests locally for testing:
  ```bash
  kubectl apply -f infra/platform/<component> -n <namespace>
  kubectl rollout status deployment/<deployment> -n <namespace>
  ```
- Rollback a deployment:
  ```bash
  kubectl rollout undo deployment/<deployment> -n <namespace>
  ```

---

## Backups & Restore

### Etcd / k3s snapshots
- Snapshots written to `<ETCD_SNAP_BUCKET>`. Use the same S3/GCS credentials as the cluster.
- List snapshots (example with gsutil):
  ```bash
  gsutil ls gs://<ETCD_SNAP_BUCKET>
  ```
- High-level restore summary:
  1. Identify the snapshot to restore.
  2. Provision a recovery server with the same k3s version.
  3. Transfer snapshot to recovery server and follow the k3s/etcd restore steps for your version.
  4. Validate control plane before rejoining agents.

### Application DB backups (PostgreSQL)
- For self-hosted PostgreSQL (e.g., via CNPG on Kubernetes):
    - Follow the specific backup and restore procedures for the CloudNativePG operator (or your chosen operator).
    - Typically involves `Cluster` or `Backup` resources.
- For managed PostgreSQL services (e.g., AWS RDS, GCP Cloud SQL):
    - Use the cloud provider's native backup and restore functionality.
    - Ensure automated backups are configured and tested.
- **Key Actions:**
    1. Verify backup frequency, retention policies, and recovery point objectives (RPOs).
    2. Test DB restores at least quarterly in a staging environment to validate procedures and RTOs.
    3. Ensure necessary credentials and access roles for backup/restore operations are secured.

---

## Troubleshooting Checklist (Incident Triage)
Follow this order and record every action in the incident log.

1. Scope & impact
   - What services/users are impacted? Regions? Severity?
2. Alerts & metrics
   - Check Prometheus/Grafana and cloud metrics/alerts.
3. Cluster health
   - `kubectl get nodes`
   - `kubectl get pods -A | grep -E 'CrashLoopBackOff|Error|Pending'`
4. Ingress & LB
   - Check cloud LB target health and `kubectl get svc -n ingress-nginx`
   - `kubectl logs -n ingress-nginx <pod>`
5. Application health
   - `kubectl get pods -n <ns>`
   - `kubectl logs -n <ns> <pod> --tail=200`
   - `kubectl exec -it -n <ns> <pod> -- /bin/sh` (investigate runtime)
6. **Database Health**
   - Check database container status: `docker ps | grep <DB_CONTAINER_NAME>`
   - Check database logs (for Docker Compose): `docker compose logs db`
   - Attempt to connect and run a simple query (see Appendix for commands).
   - If using a managed service, check cloud provider database dashboards/logs.
7. Recent changes
   - Inspect recent Terraform and manifest PRs, CI runs, and deployments.
8. Node-level checks (direct SSH)
   - `journalctl -u k3s -n 200`
   - `systemctl status containerd` or `docker ps`
   - Disk, memory, CPU pressure: `df -h`, `free -m`, `top`
9. If infra change is root cause
   - Revert Terraform to prior state or follow rollback playbook.
10. Escalation
    - If unresolved in 30 minutes, notify on-call lead and escalate per incident process.

---

## Emergency Playbooks (Top 3)

### A. Ingress / Public API is down
1. Verify LB health and ingress pods:
   - Cloud console LB targets and `kubectl get pods -n ingress-nginx`.
2. If ingress pods CrashLoop:
   - `kubectl logs -n ingress-nginx <pod>`
   - Inspect configmaps and TLS secrets.
3. Divert traffic temporarily via provider LB to a maintenance page or alternate backend.
4. Roll back ingress deployment:
   ```bash
   kubectl rollout undo deployment/<ingress-deployment> -n ingress-nginx
   ```
5. If still down, open a high-priority incident and consider restoring a control plane snapshot only if control plane is irrecoverable.

### B. Control plane (k3s server) unhealthy / API unreachable
1. Access control plane node via provider tooling:
   - `gcloud compute ssh <instance> --project=<PROJECT_ID> --zone=<ZONE>`
2. Inspect k3s:
   - `journalctl -u k3s -n 500`
   - `systemctl status k3s`
3. Attempt restart if safe and expected:
   - `systemctl restart k3s`
4. If etcd corruption suspected, coordinate senior on-call and prepare restore from latest verified snapshot. Do not rejoin agents until control plane validated.

### C. Data loss / database corruption
1. **Immediately Isolate:** Isolate the affected database instance to prevent further data modification. Consider taking the system read-only or stopping application access.
2. **Assess Impact:** Determine the extent of data loss or corruption (e.g., point in time of last good state).
3. **Restore Strategy:**
    - Identify the latest verified good backup.
    - If the database is part of a Kubernetes cluster (e.g., CNPG), explore restoring using a previous `Backup` resource or by recreating the cluster from a volume snapshot.
    - For managed services, use the provider's point-in-time recovery or snapshot restore.
4. **Validation:** Restore the chosen backup to a *staging* environment first. Thoroughly validate data integrity and application functionality.
5. **Controlled Cutover:** Coordinate a controlled cutover with product and on-call teams. Communicate risks, expected downtime, and recovery time objective (RTO).
6. **Post-Incident Analysis:** After recovery, conduct a root cause analysis to understand why corruption occurred and implement preventative measures.

---

## Maintenance & Upgrades
- Schedule maintenance windows and notify stakeholders.
- Test all upgrades in staging.
- Node upgrade flow:
  1. `kubectl drain <node> --ignore-daemonsets --delete-local-data`
  2. SSH to node and apply OS/agent updates.
  3. Restart k3s agent/server as needed.
  4. `kubectl uncordon <node>`
  5. Verify workloads: `kubectl get pods -n <ns>`
- For cluster upgrades, follow k3s-specific upgrade notes for the target version.
- Database upgrades: Follow specific procedures for your database (operator, managed service, or manual). Always test in staging.

---

## Observability & Logs
- Dashboards: Prometheus + Grafana for cluster/app/database metrics.
- Alerts: Tune P1/P2 thresholds to avoid alert fatigue; include database-specific alerts (e.g., high connection count, slow queries, disk usage).
- Logging: Centralized logging (Cloud Logging / ELK / Loki) and retention policies for application and database logs.
- Tracing: Ensure sampling supports root-cause analysis when enabled.

---

## Security & Secrets Handling
- Store secrets in GCP Secret Manager / Vault or use CI-protected variables.
- Rotate keys immediately on suspected compromise.
- Monitor TLS certificate expiry and automate renewal where possible.
- Implement principle of least privilege for database access.
- Do not post PoCs or secrets in public channels. Use private, auditable security channels per `SECURITY.md`.

---

## Change Control & PR Process (Infra)
All Terraform and manifest changes must:
1. Be developed in a branch.
2. Include a Terraform plan or manifest diff in the PR.
3. Include a short runbook note if the change affects recovery or operations.
4. Have at least one approver review the plan and impact.
5. Be applied during approved maintenance windows for high-risk changes.

---

## Runbook Hygiene & Post-Incident
- After incidents, publish a postmortem with timeline, root cause, remediation, and action items.
- Update this runbook for any changed or missing steps discovered during incidents.
- Verify backups and run a restore test at least quarterly.

---

## Appendix — Common Commands

### Kubernetes:
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-system
kubectl logs -n <ns> <pod> --tail=200
kubectl exec -it -n <ns> <pod> -- /bin/sh
```

### Terraform:
```bash
cd infra
terraform init
terraform validate
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

### GCP SSH (example):
```bash
gcloud compute ssh <INSTANCE_NAME> --project=<PROJECT_ID> --zone=<ZONE>
```

### Etcd snapshots:
```bash
gsutil ls gs://<ETCD_SNAP_BUCKET>
```

### Database (PostgreSQL - Local Docker Example):
- **Connect to local DB via Taskfile:**
  ```bash
  task db:login
  ```
  *(This task uses `docker exec -it project-platform-db-1 psql -U platform platform_db`)*

- **Direct Docker exec (if Taskfile not used):**
  ```bash
  docker exec -it <DB_CONTAINER_NAME> psql -U <DB_USER> <DB_NAME>
  ```
  *(Example: `docker exec -it project-platform-db-1 psql -U platform platform_db`)*

- **List databases:**
  ```sql
  \l
  ```
- **Connect to a specific database (from psql prompt):**
  ```sql
  \c <DB_NAME>
  ```
- **List tables in current database:**
  ```sql
  \dt
  ```
- **Describe a table schema:**
  ```sql
  \d <TABLE_NAME>
  ```
- **List users/roles:**
  ```sql
  \du
  ```
- **Basic SQL Query Examples:**
  ```sql
  -- Select all rows and columns from a table
  SELECT * FROM users;

  -- Select specific columns with a condition
  SELECT id, name FROM products WHERE price > 100;

  -- Insert a new row
  INSERT INTO orders (user_id, product_id, quantity) VALUES (1, 101, 2);

  -- Update existing rows
  UPDATE users SET email = 'new.email@example.com' WHERE id = 5;

  -- Delete rows
  DELETE FROM products WHERE stock = 0;
  ```

---

## Revision history
- v3.2 — Added comprehensive database sections, including common commands, troubleshooting, and enhanced backup/restore guidance. Removed unformatted commands at EOF. Update date: 2024-07-30
- v3.1 — removed bastion/NAT and Helm references; switched to manifests and direct node access. Update date: YYYY-MM-DD