# Runbook

Operational procedures for provisioning, deploying, and operating the project-platform infrastructure.

> See [README.md](./README.md) for stack overview and local dev setup.
> See [K8s.md](./K8s.md) for kubectl/ArgoCD/Cilium/CNPG command reference.
> See [POSTGRES.md](./POSTGRES.md) for PostgreSQL and CNPG command reference.

---

## Security Rules

- Never commit secrets, private keys, or service account JSON to the repository.
- Use `.env` (gitignored) for local development credentials.
- Use Sealed Secrets for all in-cluster secrets.
- GCS service account JSON for Terraform remote state lives in `keys/` (gitignored).

---

## Preflight Checklist

Before any provisioning or deployment operation, verify:

```bash
task --version
terraform --version
kubectl version --client
packer --version
buf --version
go version
kubeseal --version
tailscale version
```

> ArgoCD runs on the cluster — no local CLI install needed. Interact via port-forward or the UI (see section C).

Verify `.env` is populated:
- `HCLOUD_TOKEN`
- `DO_TOKEN`
- `WORKOS_CLIENT_ID`, `WORKOS_CLIENT_SECRET`
- `DATABASE_URL`
- GCS credentials path for Terraform backend

---

## Cluster Access via Tailscale

The K3s API server listens on the node's **Tailscale IP** (not the public IP). kubectl will not reach the cluster unless Tailscale is connected on your machine.

### 1. Connect Tailscale

```bash
tailscale up
tailscale status          # confirm the control plane node appears and is online
tailscale ping <node-tailscale-hostname>   # verify reachability
```

### 2. Fetch the kubeconfig

`task hz:kubeconfig` (or `task do:kubeconfig`) pulls the kubeconfig from the cluster and merges it into `~/.kube/config`. Terraform patches the `server:` address to the Tailscale IP of the control plane node automatically.

```bash
task hz:kubeconfig     # fetch + merge for Hetzner cluster
task do:kubeconfig     # fetch + merge for DigitalOcean cluster
```

### 3. Verify kubectl is pointing at the right cluster

```bash
kubectl config current-context      # confirm context name
kubectl config get-contexts         # list all contexts
kubectl cluster-info                # should show the Tailscale IP, not 127.0.0.1
kubectl get nodes -o wide           # nodes should appear
```

### If kubectl times out

The most common causes:
1. **Tailscale is not connected** — run `tailscale up` and retry.
2. **Wrong server address in kubeconfig** — the `server:` field must be the Tailscale IP, not a public or internal IP. Check with:
   ```bash
   kubectl config view --minify | grep server
   # Should be: https://<tailscale-ip>:6443
   ```
   If it shows the wrong address, re-run `task hz:kubeconfig` or patch it manually:
   ```bash
   kubectl config set-cluster <cluster-name> --server=https://<tailscale-ip>:6443
   ```
3. **Wrong context active** — run `kubectl config use-context <correct-context>`.
4. **Node is down** — check Hetzner console or Terraform state.

### Switching between clusters (Hetzner ↔ DigitalOcean)

```bash
kubectl config get-contexts
kubectl config use-context <context-name>
kubectl config current-context
```

Install `kubectx` for faster switching: `kubectx <context-name>`.

---

## A. Build Golden Images (Packer)

Packer images bake in K3s, gVisor (`runsc`), and Tailscale. Images are used as the base for all Terraform-provisioned nodes.

```bash
task packer:hz:k3s     # Hetzner — K3s node image
task packer:hz:nat     # Hetzner — NAT gateway image
task packer:do:k3s     # DigitalOcean — K3s node image (fallback)
task packer:do:nat     # DigitalOcean — NAT gateway image (fallback)
```

After a build, update the Terraform variable that references the snapshot/image ID before provisioning new nodes.

---

## B. Infrastructure Provisioning (Terraform)

Terraform state is stored remotely in GCS. Each provider has its own state file.

### Hetzner (primary)

```bash
task hz:plan        # preview changes
task hz:apply       # provision / update infrastructure
task hz:output      # show Terraform outputs (IPs, etc.)
task hz:kubeconfig  # fetch and merge kubeconfig for the cluster
task hz:destroy     # DESTRUCTIVE — tears down all Hetzner resources
```

### DigitalOcean (secondary/fallback)

```bash
task do:plan
task do:apply
task do:output
task do:kubeconfig
task do:destroy     # DESTRUCTIVE
```

After `hz:apply` or `do:apply`, Terraform bootstraps the cluster by applying manifests from `infrastructure/terraform/modules/k3s_node/bootstrap/`. This installs ArgoCD and registers the root App of Apps. All subsequent platform component management is handled by ArgoCD.

---

## C. GitOps — ArgoCD

ArgoCD runs on the cluster and watches this repo. There is no local ArgoCD CLI install. All deployments happen via Git — push to `main` and ArgoCD picks it up.

All platform component manifests live under `infrastructure/argocd`. Do not `kubectl apply` directly for anything ArgoCD manages.

### Normal workflow

```
1. Edit manifests in infrastructure/argocd
2. Commit and push to main
3. ArgoCD auto-syncs — done
```

### Check sync status (via kubectl)

```bash
# ArgoCD app resources
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd

# ArgoCD pods healthy
kubectl get pods -n argocd

# Events (shows sync errors)
kubectl get events -n argocd --sort-by='.lastTimestamp'
```

### Access ArgoCD UI (port-forward to cluster)

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# Open https://localhost:8080
# Admin password:
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

If you have the `argocd` CLI installed locally (optional), point it at the port-forwarded server:

```bash
argocd login localhost:8080 --insecure --username admin --password <password>
argocd app list
argocd app sync <app-name>
argocd app diff <app-name>
argocd app rollback <app-name> <revision>
```

---

## D. Sealed Secrets

All in-cluster secrets must be sealed before committing to Git.

```bash
# Fetch the controller public cert (do this once per cluster, store cert locally)
kubeseal --fetch-cert \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller > pub-cert.pem

# Create and seal a secret
kubectl create secret generic <name> \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --cert pub-cert.pem --format yaml > sealed-secret.yaml

# Apply the sealed secret
kubectl apply -f sealed-secret.yaml -n <ns>

# Verify the secret was decrypted
kubectl get secret <name> -n <ns>
```

---

## E. Platform Health Check

Run these after any provisioning, deployment, or incident.

### Nodes

```bash
kubectl get nodes -o wide
kubectl top nodes
```

### Core Platform Components

```bash
# ArgoCD — all apps in sync and healthy (kubectl, no local CLI needed)
kubectl get applications -n argocd

# CNPG — database cluster healthy
kubectl get cluster -A
kubectl cnpg status <cluster-name> -n <ns>

# Cilium — network data plane healthy
cilium status

# ingress-nginx
kubectl get pods -n ingress-nginx

# cert-manager — no failing certificate requests
kubectl get certificates -A
kubectl get challenges -A

# Sealed Secrets controller
kubectl get pods -n kube-system -l name=sealed-secrets-controller

# KubeArmor
kubectl get pods -n kubearmor

# Kyverno
kubectl get pods -n kyverno
kubectl get clusterpolicies
kubectl get policyreports -A
```

### Observability Stack

```bash
kubectl get pods -n monitoring    # VictoriaMetrics, Grafana
kubectl get pods -n logging       # Loki, Fluent Bit
```

---

## F. Local Database (Development)

```bash
task db:setup                           # first time: up + migrate + sqlc generate
task db:up                              # start Postgres container
task db:down                            # stop container
task db:migrate                         # apply pending migrations
task db:migrate-down                    # roll back one migration
task db:create-migration NAME=<name>    # scaffold new migration files
task db:generate                        # run sqlc generate
task db:login                           # psql shell into local DB
```

---

## G. Code Generation

```bash
task proto:gen      # buf generate — ConnectRPC stubs from proto/
task proto:lint     # buf lint
task db:generate    # sqlc generate from core/queries/
templ generate      # Templ → Go (run after editing any .templ file)
go build ./...      # verify no compilation errors
```

---

## H. Backups

### etcd (K3s)

K3s automatically creates etcd snapshots. Snapshots are stored in S3-compatible storage (configured via k3s flags on the control plane in Terraform).

```bash
# Verify snapshot config
kubectl -n kube-system get pods -l component=etcd

# Manual snapshot (if needed)
k3s etcd-snapshot save --name manual-$(date +%F)

# List snapshots
k3s etcd-snapshot list
```

### PostgreSQL (CNPG)

CNPG handles WAL archiving and scheduled base backups. Backup target is GCS (internal).

```bash
# Trigger a manual backup
kubectl cnpg backup <cluster-name> -n <ns>

# Check backup status
kubectl get backups -n <ns>
kubectl describe backup <backup-name> -n <ns>

# Scheduled backup config
kubectl get scheduledbackups -n <ns>
```

---

## I. Incident Response

### Pod stuck in CrashLoopBackOff

```bash
kubectl describe pod <pod> -n <ns>           # check Events section
kubectl logs <pod> -n <ns> --previous        # logs from crashed container
kubectl logs <pod> -n <ns> -c <container>    # if multi-container
```

### Node NotReady

```bash
kubectl describe node <node>                 # check Conditions and Events
kubectl get events -A --sort-by='.lastTimestamp' | grep -i <node>
# SSH to node via Tailscale, check k3s service:
sudo systemctl status k3s
sudo journalctl -u k3s -f
```

### Ingress / TLS not working

```bash
kubectl describe ingress <name> -n <ns>
kubectl get certificates -n <ns>
kubectl describe certificate <name> -n <ns>
kubectl get challenges -n <ns>
kubectl logs -n cert-manager -l app=cert-manager -f
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f
```

### CNPG primary down / failover

```bash
kubectl get pods -n <ns> -l cnpg.io/cluster=<cluster-name>
kubectl cnpg status <cluster-name> -n <ns>
# CNPG promotes a standby automatically. Verify new primary:
kubectl get pods -n <ns> -l cnpg.io/instanceRole=primary
# Check replication lag from new primary:
kubectl cnpg psql <cluster-name> -n <ns> -- \
  -c "SELECT * FROM pg_stat_replication;"
```

### Dropped network traffic (Cilium)

```bash
cilium status
hubble observe --verdict DROPPED -n <ns> --follow
kubectl exec -n kube-system <cilium-pod> -- cilium monitor --type drop
kubectl get cnp -n <ns>    # check CiliumNetworkPolicy
```

### ArgoCD app OutOfSync

ArgoCD syncs automatically on push to `main`. If something is stuck:

```bash
# Check app status and events via kubectl
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
kubectl get events -n argocd --sort-by='.lastTimestamp'

# Force a re-sync via port-forward + argocd CLI (if installed locally)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &
argocd login localhost:8080 --insecure --username admin --password <password>
argocd app sync <app-name> --prune
argocd app diff <app-name>
```

### Kyverno blocking a resource

```bash
kubectl get policyreports -A
kubectl describe clusterpolicy <policy-name>
# Check admission webhook events:
kubectl get events -n <ns> --field-selector=reason=PolicyViolation
```

---

## J. Upgrade Procedures

### K3s version upgrade

```bash
# 1. Update k3s version in Packer template
# 2. Build new golden image: task packer:hz:k3s
# 3. Update image reference in Terraform
# 4. Rolling node replacement via Terraform (drain → replace → uncordon)
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
# After node replaced:
kubectl uncordon <node>
```

### Platform component upgrade (ArgoCD-managed)

```bash
# 1. Update chart version or image tag in infrastructure/kubernetes/manifests/
# 2. Commit and push to main — ArgoCD auto-syncs
# 3. Verify sync via kubectl:
kubectl get applications -n argocd
kubectl describe application <app-name> -n argocd
```

### CNPG upgrade

Follow CloudNativePG upgrade docs. Generally: update the operator first, then the cluster CR `imageName` field.

```bash
# Update operator (via ArgoCD manifest update)
# Then update cluster image:
kubectl patch cluster <cluster-name> -n <ns> \
  --type=merge -p '{"spec":{"imageName":"ghcr.io/cloudnative-pg/postgresql:<new-version>"}}'
kubectl cnpg status <cluster-name> -n <ns>   # watch rolling update
```

---

## K. Terraform State Issues

If a `task hz:*` or `task do:*` command fails with backend errors:

1. Verify GCS credentials path in `.env` matches the `keys/` directory.
2. Check the backend config in `Taskfile.yml` — bucket name and prefix must match the actual GCS bucket.
3. Run `terraform init -reconfigure` inside the relevant provider directory if the backend has changed.
4. Never run `terraform force-unlock` without confirming no other operator holds the lock.
