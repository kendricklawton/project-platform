Here's a solid rundown of the essential `kubectl` and cluster management commands every K8s admin should have committed to muscle memory.

---

## Cluster & Node Info

```bash
kubectl cluster-info
kubectl get nodes -o wide
kubectl describe node <node-name>
kubectl top nodes
kubectl cordon <node>          # mark unschedulable
kubectl uncordon <node>        # mark schedulable again
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
```

## Workloads (Pods, Deployments, StatefulSets, DaemonSets)

```bash
kubectl get pods -A                          # all namespaces
kubectl get pods -n <ns> -o wide             # with node/IP info
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> -c <container>    # specific container
kubectl logs <pod> -n <ns> --previous        # crashed container logs
kubectl logs -f <pod> -n <ns>                # follow/stream
kubectl exec -it <pod> -n <ns> -- /bin/sh    # shell into pod
kubectl port-forward <pod> 8080:80 -n <ns>

kubectl get deployments -A
kubectl describe deployment <name> -n <ns>
kubectl scale deployment <name> --replicas=5 -n <ns>
kubectl rollout status deployment/<name> -n <ns>
kubectl rollout history deployment/<name> -n <ns>
kubectl rollout undo deployment/<name> -n <ns>
kubectl rollout restart deployment/<name> -n <ns>

kubectl get statefulsets -A
kubectl get daemonsets -A
kubectl get replicasets -A
```

## Services & Networking

```bash
kubectl get svc -A
kubectl describe svc <name> -n <ns>
kubectl get endpoints -n <ns>
kubectl get ingress -A
kubectl get networkpolicies -A
```

## Config, Secrets & Storage

```bash
kubectl get configmaps -n <ns>
kubectl get secrets -n <ns>
kubectl get secret <name> -n <ns> -o jsonpath='{.data.<key>}' | base64 -d

kubectl get pv                  # persistent volumes (cluster-wide)
kubectl get pvc -n <ns>         # persistent volume claims
kubectl get storageclass
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
kubectl auth can-i '*' '*' --as=system:serviceaccount:<ns>:<sa>   # check SA perms
```

## Resource Management & Debugging

```bash
kubectl top pods -n <ns>
kubectl get events -n <ns> --sort-by='.lastTimestamp'
kubectl get all -n <ns>

# Debug a running pod
kubectl debug <pod> -it --image=busybox -n <ns>

# Run a throwaway pod for troubleshooting
kubectl run debug --rm -it --image=nicolaka/netshoot -- /bin/bash

# Dry-run + diff before applying
kubectl apply -f manifest.yaml --dry-run=server
kubectl diff -f manifest.yaml
```

## Apply, Delete & Edit

```bash
kubectl apply -f <file-or-dir>
kubectl delete -f <file-or-dir>
kubectl delete pod <pod> -n <ns> --grace-period=0 --force   # force kill
kubectl edit deployment <name> -n <ns>
kubectl patch deployment <name> -n <ns> -p '{"spec":{"replicas":3}}'
```

## Output & Filtering Power Moves

```bash
kubectl get pods -o yaml                         # full YAML
kubectl get pods -o json | jq '.items[].metadata.name'
kubectl get pods -l app=nginx -n <ns>            # label selector
kubectl get pods --field-selector=status.phase=Running
kubectl get pods --sort-by='.status.startTime'
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase

# Explain any resource field
kubectl explain pod.spec.containers.resources
```

## Context & Kubeconfig

```bash
kubectl config get-contexts
kubectl config use-context <context>
kubectl config current-context
kubectl config view --minify          # show current context config only
export KUBECONFIG=~/.kube/config:~/.kube/other-cluster   # merge configs
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
```

---

**Pro tips:** Install `kubectx`/`kubens` for fast context and namespace switching, alias `k=kubectl`, and use `k9s` for a terminal UI that makes navigating clusters dramatically faster. If you're doing CKA/CKAD prep, get comfortable with `--dry-run=client -o yaml` as your manifest generator — it's a huge time saver.
