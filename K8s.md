## Cluster & Node Info

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl describe node <node-name>
kubectl top nodes
kubectl cordon <node>          # mark unschedulable
kubectl uncordon <node>        # mark schedulable again
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data

# Node labels & taints
kubectl get nodes --show-labels
kubectl label node <node> role=worker
kubectl taint node <node> key=value:NoSchedule
kubectl taint node <node> key=value:NoSchedule-   # remove taint
```

## Workloads (Pods, Deployments, StatefulSets, DaemonSets)

```bash
kubectl get pods -A                          # all namespaces
kubectl get pods -n <ns> -o wide             # with node/IP info
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> -c <container>    # specific container
kubectl logs <pod> -n <ns> --previous        # crashed container logs
kubectl logs -f <pod> -n <ns>                # follow/stream
kubectl logs <pod> -n <ns> --tail=100
kubectl exec -it <pod> -n <ns> -- /bin/sh    # shell into pod
kubectl port-forward <pod> 8080:80 -n <ns>
kubectl port-forward svc/<svc> 8080:80 -n <ns>

kubectl get deployments -A
kubectl describe deployment <name> -n <ns>
kubectl scale deployment <name> --replicas=5 -n <ns>
kubectl rollout status deployment/<name> -n <ns>
kubectl rollout history deployment/<name> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>
kubectl rollout undo deployment/<name> --to-revision=2 -n <ns>
kubectl rollout restart deployment/<name> -n <ns>

kubectl get statefulsets -A
kubectl get daemonsets -A
kubectl get replicasets -A
kubectl get jobs -A
kubectl get cronjobs -A

# Watch pod status in real time
kubectl get pods -n <ns> -w

# Show pod resource requests/limits
kubectl get pods -n <ns> -o custom-columns=\
'NAME:.metadata.name,CPU_REQ:.spec.containers[*].resources.requests.cpu,MEM_REQ:.spec.containers[*].resources.requests.memory'
```

## Services & Networking

```bash
kubectl get svc -A
kubectl describe svc <name> -n <ns>
kubectl get endpoints -n <ns>
kubectl get ingress -A
kubectl describe ingress <name> -n <ns>
kubectl get networkpolicies -A
kubectl describe networkpolicy <name> -n <ns>

# DNS debug
kubectl run dnstest --rm -it --image=busybox --restart=Never -- nslookup <svc>.<ns>.svc.cluster.local
```

## Config, Secrets & Storage

```bash
kubectl get configmaps -n <ns>
kubectl describe configmap <name> -n <ns>
kubectl get secrets -n <ns>
kubectl get secret <name> -n <ns> -o jsonpath='{.data.<key>}' | base64 -d
kubectl create secret generic <name> --from-literal=key=value -n <ns>

kubectl get pv                  # persistent volumes (cluster-wide)
kubectl get pvc -n <ns>         # persistent volume claims
kubectl describe pvc <name> -n <ns>
kubectl get storageclass
kubectl get volumesnapshots -A
```

## Namespaces & RBAC

```bash
kubectl get namespaces
kubectl create namespace <name>
kubectl config set-context --current --namespace=<ns>   # switch default ns

kubectl get serviceaccounts -n <ns>
kubectl get roles,rolebindings -n <ns>
kubectl get clusterroles,clusterrolebindings
kubectl auth can-i <verb> <resource> --as=<user> -n <ns>
kubectl auth can-i '*' '*' --as=system:serviceaccount:<ns>:<sa>
kubectl auth whoami
```

## Resource Management & Debugging

```bash
kubectl top pods -n <ns>
kubectl top pods -n <ns> --sort-by=memory
kubectl get events -n <ns> --sort-by='.lastTimestamp'
kubectl get events -A --field-selector=type=Warning
kubectl get all -n <ns>

# Debug a running pod (ephemeral container)
kubectl debug <pod> -it --image=busybox -n <ns>
kubectl debug <pod> -it --image=nicolaka/netshoot --copy-to=debug-pod -n <ns>

# Run a throwaway pod for troubleshooting
kubectl run debug --rm -it --image=nicolaka/netshoot -- /bin/bash

# Check resource quota usage
kubectl describe resourcequota -n <ns>
kubectl describe limitrange -n <ns>

# Dry-run + diff before applying
kubectl apply -f manifest.yaml --dry-run=server
kubectl diff -f manifest.yaml

# Force-delete stuck namespace
kubectl get namespace <ns> -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw "/api/v1/namespaces/<ns>/finalize" -f -
```

## Apply, Delete & Edit

```bash
kubectl apply -f <file-or-dir>
kubectl apply -k <kustomize-dir>
kubectl delete -f <file-or-dir>
kubectl delete pod <pod> -n <ns> --grace-period=0 --force   # force kill
kubectl edit deployment <name> -n <ns>
kubectl patch deployment <name> -n <ns> -p '{"spec":{"replicas":3}}'
kubectl patch deployment <name> -n <ns> --type=json \
  -p='[{"op":"replace","path":"/spec/replicas","value":2}]'

# Set image directly
kubectl set image deployment/<name> <container>=<image>:<tag> -n <ns>
kubectl annotate deployment <name> -n <ns> kubernetes.io/change-cause="reason"
```

## Output & Filtering Power Moves

```bash
kubectl get pods -o yaml                         # full YAML
kubectl get pods -o json | jq '.items[].metadata.name'
kubectl get pods -l app=nginx -n <ns>            # label selector
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --field-selector=spec.nodeName=<node>
kubectl get pods --sort-by='.status.startTime'
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName

# All images running in cluster
kubectl get pods -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.image}{"\n"}{end}{end}'

# Explain any resource field
kubectl explain pod.spec.containers.resources
kubectl explain deployment.spec.strategy
```

## Context & Kubeconfig

```bash
kubectl config get-contexts
kubectl config use-context <context>
kubectl config current-context
kubectl config view --minify          # show current context config only
kubectl config rename-context <old> <new>
export KUBECONFIG=~/.kube/config:~/.kube/other-cluster   # merge configs

# kubectx/kubens (install separately)
kubectx                    # list contexts
kubectx <context>          # switch context
kubens                     # list namespaces
kubens <ns>                # switch namespace
```

## K3s Specific

```bash
# Service management (systemd)
sudo systemctl status k3s
sudo systemctl restart k3s
sudo journalctl -u k3s -f

# Kubeconfig location
/etc/rancher/k3s/k3s.yaml

# Node token (for adding agents)
sudo cat /var/lib/rancher/k3s/server/node-token

# k3s built-in tools
k3s kubectl get nodes
k3s crictl ps                     # list containers (CRI)
k3s crictl images                 # list images
k3s crictl logs <container-id>

# Check k3s version
k3s --version

# Uninstall
/usr/local/bin/k3s-uninstall.sh         # server
/usr/local/bin/k3s-agent-uninstall.sh   # agent
```

## ArgoCD (GitOps)

```bash
# CLI login
argocd login <argocd-server> --username admin --password <password>
argocd login <argocd-server> --sso

# App management
argocd app list
argocd app get <app-name>
argocd app diff <app-name>
argocd app sync <app-name>
argocd app sync <app-name> --force
argocd app sync <app-name> --prune
argocd app history <app-name>
argocd app rollback <app-name> <revision>
argocd app delete <app-name>
argocd app create <app-name> \
  --repo https://github.com/org/repo \
  --path k8s/ \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace default

# Manual refresh (re-fetch from Git)
argocd app get <app-name> --refresh

# Watch sync status
argocd app wait <app-name> --sync --health --timeout 120

# Repo management
argocd repo list
argocd repo add https://github.com/org/repo --username <user> --password <token>

# Cluster management
argocd cluster list
argocd cluster add <context>

# Admin password reset
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d

# Port-forward ArgoCD UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

## Cilium & Hubble

```bash
# Cilium CLI status
cilium status
cilium status --wait

# Connectivity test
cilium connectivity test

# List Cilium-managed endpoints
kubectl get cep -A   # CiliumEndpoint

# Network policy inspection
kubectl get cnp -A   # CiliumNetworkPolicy
kubectl get ccnp -A  # CiliumClusterwideNetworkPolicy
kubectl describe cnp <name> -n <ns>

# Hubble (observability)
hubble status
hubble observe --follow
hubble observe -n <ns> --follow
hubble observe --pod <pod> -n <ns>
hubble observe --verdict DROPPED
hubble observe --type l7
hubble observe --protocol http --follow

# Port-forward Hubble UI
kubectl port-forward svc/hubble-ui -n kube-system 12000:80

# Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium -f

# Check eBPF map state
kubectl exec -n kube-system <cilium-pod> -- cilium endpoint list
kubectl exec -n kube-system <cilium-pod> -- cilium policy get
kubectl exec -n kube-system <cilium-pod> -- cilium monitor --type drop
```

## Sealed Secrets

```bash
# Encrypt a secret (requires kubeseal CLI + controller running)
kubectl create secret generic <name> \
  --from-literal=key=value \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  --format yaml > sealed-secret.yaml

# Encrypt from existing secret file
kubeseal < secret.yaml > sealed-secret.yaml

# Fetch controller public cert
kubeseal --fetch-cert \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller > pub-cert.pem

# Encrypt offline using fetched cert
kubeseal --cert pub-cert.pem < secret.yaml > sealed-secret.yaml

# Check controller status
kubectl get pods -n kube-system -l name=sealed-secrets-controller
kubectl logs -n kube-system -l name=sealed-secrets-controller

# List all SealedSecrets
kubectl get sealedsecrets -A
```

## cert-manager

```bash
# Check cert-manager pods
kubectl get pods -n cert-manager

# List certificates
kubectl get certificates -A
kubectl get certificaterequests -A
kubectl get orders -A
kubectl get challenges -A

# Describe a certificate (check Ready status + expiry)
kubectl describe certificate <name> -n <ns>

# Force renewal
kubectl annotate certificate <name> -n <ns> \
  cert-manager.io/issuer-kind=ClusterIssuer \
  --overwrite
# Or delete the secret to trigger re-issue:
kubectl delete secret <tls-secret-name> -n <ns>

# Check ClusterIssuers / Issuers
kubectl get clusterissuers
kubectl get issuers -A
kubectl describe clusterissuer letsencrypt-prod
```

## Ingress NGINX

```bash
# Check controller pods
kubectl get pods -n ingress-nginx

# List all ingress resources
kubectl get ingress -A

# Check controller config
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml

# View access logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# Test ingress reachability
kubectl run test --rm -it --image=curlimages/curl -- \
  curl -H "Host: <hostname>" http://<ingress-svc-ip>

# Reload nginx without restart (happens automatically on configmap change)
kubectl annotate ingress <name> -n <ns> nginx.ingress.kubernetes.io/rewrite-target=/
```

## CloudNativePG (CNPG)

```bash
# Install CNPG plugin for kubectl
# https://cloudnative-pg.io/documentation/current/kubectl-plugin/

# Cluster status
kubectl get cluster -A
kubectl describe cluster <cluster-name> -n <ns>

# Pod roles (primary vs replica)
kubectl get pods -n <ns> -l cnpg.io/cluster=<cluster-name>
kubectl get pods -n <ns> -l cnpg.io/instanceRole=primary

# Connect to primary via plugin
kubectl cnpg psql <cluster-name> -n <ns>

# Manual switchover (promote a standby)
kubectl cnpg promote <cluster-name> <pod-name> -n <ns>

# Backup
kubectl cnpg backup <cluster-name> -n <ns>
kubectl get backups -n <ns>
kubectl describe backup <backup-name> -n <ns>

# Scheduled backups
kubectl get scheduledbackups -n <ns>

# Check WAL archiving status
kubectl cnpg status <cluster-name> -n <ns>

# Restart a CNPG instance
kubectl delete pod <cnpg-pod> -n <ns>   # controller recreates it

# Logs
kubectl logs <cnpg-pod> -n <ns> -c postgres
kubectl logs <cnpg-pod> -n <ns> -c pgbouncer   # if using pooler
```

## Helm

```bash
helm repo add <name> <url>
helm repo update
helm repo list

helm search repo <chart>
helm show values <repo>/<chart>

helm install <release> <repo>/<chart> -n <ns> --create-namespace
helm install <release> <repo>/<chart> -f values.yaml -n <ns>
helm upgrade <release> <repo>/<chart> -n <ns>
helm upgrade --install <release> <repo>/<chart> -n <ns> -f values.yaml
helm rollback <release> <revision> -n <ns>
helm uninstall <release> -n <ns>

helm list -A
helm status <release> -n <ns>
helm get values <release> -n <ns>
helm get manifest <release> -n <ns>
helm history <release> -n <ns>

# Render templates locally without installing
helm template <release> <repo>/<chart> -f values.yaml
# Dry run against cluster
helm install <release> <repo>/<chart> --dry-run --debug
```

## Kyverno (Policy Engine)

```bash
kubectl get policies -A          # namespaced policies
kubectl get clusterpolicies       # cluster-wide policies
kubectl get policyreports -A
kubectl get clusterpolicyreports
kubectl describe clusterpolicy <name>

# Check policy violations
kubectl get policyreports -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{range .results[?(@.result=="fail")]}{.rule}{"\n"}{end}{end}'
```

## KubeArmor

```bash
kubectl get pods -n kubearmor
kubectl get kubearmorsecuritypolicies -A   # KSP
kubectl get kubearmorclusterpolicies       # cluster-wide

kubectl logs -n kubearmor -l kubearmor-app=kubearmor -f

# karmor CLI
karmor probe         # check kubearmor status
karmor logs          # stream enforced/blocked logs
karmor logs --json   # JSON format
karmor summary       # per-pod security summary
```

## Etcd & Certificates (Control Plane)

```bash
# etcd snapshot (kubeadm clusters)
ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-table

# Check certificate expiry (kubeadm)
kubeadm certs check-expiration
kubeadm certs renew all
```

## Quick Generators

```bash
kubectl create deployment nginx --image=nginx --replicas=3 --dry-run=client -o yaml > deploy.yaml
kubectl create service clusterip my-svc --tcp=80:8080 --dry-run=client -o yaml
kubectl create configmap my-config --from-file=config.txt --dry-run=client -o yaml
kubectl create secret generic my-secret --from-literal=password=hunter2 --dry-run=client -o yaml
kubectl create job my-job --image=busybox -- echo "hello"
kubectl create cronjob my-cron --image=busybox --schedule="*/5 * * * *" -- echo "tick"

# ServiceAccount + RoleBinding boilerplate
kubectl create serviceaccount <sa> -n <ns> --dry-run=client -o yaml
kubectl create rolebinding <name> --role=<role> --serviceaccount=<ns>:<sa> -n <ns> --dry-run=client -o yaml
```

## Useful Aliases & Shell Helpers

```bash
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'
alias ke='kubectl exec -it'
alias kaf='kubectl apply -f'
alias kdf='kubectl delete -f'
alias kns='kubectl config set-context --current --namespace'

# Watch all pods across namespaces
watch -n2 kubectl get pods -A

# Get all non-running pods
kubectl get pods -A --field-selector=status.phase!=Running

# Delete all evicted pods
kubectl get pods -A | grep Evicted | awk '{print $2 " -n " $1}' | xargs -I{} kubectl delete pod {}

# Restart all deployments in a namespace
kubectl rollout restart deployment -n <ns>

# Copy file from pod
kubectl cp <ns>/<pod>:/path/to/file ./local-file

# Copy file to pod
kubectl cp ./local-file <ns>/<pod>:/path/to/file
```

---

**Pro tips:** Install `kubectx`/`kubens` for fast context/namespace switching. `k9s` is a terminal UI that makes cluster navigation dramatically faster. For GitOps, `argocd app diff` before sync saves headaches. Use `--dry-run=server` (not client) for the most accurate pre-apply validation.
