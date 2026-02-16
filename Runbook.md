# Runbook

This runbook is the single canonical source for provisioning, operating, and recovering the `project-platform` infrastructure. It is intentionally concise and action-oriented so on-call engineers and maintainers can quickly find and execute the right steps.

IMPORTANT
- Never commit secrets, private keys, or service account JSON files to the repository.
- Replace placeholders (e.g., `<PROJECT_ID>`, `<TFSTATE_BUCKET>`, `<MAINTAINER_CONTACT>`, `<NODE_PUBLIC_IP>`) with values stored in your secret manager or in environment-specific variable files that are excluded from source control.
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
3. Confirm kubeconfig/context:
   - `kubectl config current-context`
4. Confirm Terraform remote state and CI secrets are in place and protected.
5. Announce maintenance to on-call and stakeholders; record maintenance window.

---

## SSH / Node Access Pattern
We assume direct node access as needed (provider-assigned IPs or provider tooling). Do NOT commit private keys.

- Direct SSH example:
  ```
  ssh <ADMIN_USER>@<NODE_PUBLIC_IP>
  ```
- GCP example (preferred for GCP-managed keys / IAM integration):
  ```
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

### Application DB backups
- Follow DB operator/provider restore docs.
- Test DB restores at least quarterly in staging.

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
6. Recent changes
   - Inspect recent Terraform and manifest PRs, CI runs, and deployments.
7. Node-level checks (direct SSH)
   - `journalctl -u k3s -n 200`
   - `systemctl status containerd` or `docker ps`
   - Disk, memory, CPU pressure: `df -h`, `free -m`, `top`
8. If infra change is root cause
   - Revert Terraform to prior state or follow rollback playbook.
9. Escalation
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
1. Isolate write traffic and take system read-only if possible.
2. Restore a recent verified DB backup to staging and validate.
3. Coordinate a controlled cutover with product and on-call teams, communicate risk and timing.

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

---

## Observability & Logs
- Dashboards: Prometheus + Grafana for cluster/app metrics.
- Alerts: Tune P1/P2 thresholds to avoid alert fatigue.
- Logging: Centralized logging (Cloud Logging / ELK) and retention policies.
- Tracing: Ensure sampling supports root-cause analysis when enabled.

---

## Security & Secrets Handling
- Store secrets in GCP Secret Manager / Vault or use CI-protected variables.
- Rotate keys immediately on suspected compromise.
- Monitor TLS certificate expiry and automate renewal where possible.
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

Kubernetes:
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get pods -n kube-system
kubectl logs -n <ns> <pod> --tail=200
kubectl exec -it -n <ns> <pod> -- /bin/sh
```

Terraform:
```bash
cd infra
terraform init
terraform validate
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

GCP SSH (example):
```bash
gcloud compute ssh <INSTANCE_NAME> --project=<PROJECT_ID> --zone=<ZONE>
```

Etcd snapshots:
```bash
gsutil ls gs://<ETCD_SNAP_BUCKET>
```

---

## Revision history
- v3.1 — removed bastion/NAT and Helm references; switched to manifests and direct node access. Update date: YYYY-MM-DD

---


cat /var/log/cloud-init-output.log | grep -iE "critical|error|failed"

ip a

ip route add 10.0.0.0/16 dev enp7s0

/usr/local/bin/k3s-start.sh
