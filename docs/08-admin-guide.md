# 08 - Admin Guide

Day-to-day administration of the K3s cluster. This is your go-to reference for managing workloads, troubleshooting, and operating the platform.

## Table of Contents

1. [Quick Reference](#quick-reference)
2. [Accessing the UIs](#accessing-the-uis)
3. [Managing Containers (Pods)](#managing-containers-pods)
4. [Deploying a New Application](#deploying-a-new-application)
5. [Updating an Application](#updating-an-application)
6. [Running Workloads on Specific Nodes](#running-workloads-on-specific-nodes)
7. [GPU Workloads](#gpu-workloads)
8. [Troubleshooting](#troubleshooting)
9. [Scaling](#scaling)
10. [Storage Management](#storage-management)
11. [Backup and Restore](#backup-and-restore)
12. [Adding a New Node](#adding-a-new-node)
13. [Removing a Node](#removing-a-node)
14. [Monitoring and Alerts](#monitoring-and-alerts)
15. [GitOps Workflow](#gitops-workflow)
16. [Common kubectl Commands](#common-kubectl-commands)
17. [Emergency Procedures](#emergency-procedures)

---

## Quick Reference

```bash
# Set this in your shell (already in ~/.bashrc on NUC-HA)
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Cluster overview
kubectl get nodes                    # List all nodes
kubectl get pods -A                  # All pods, all namespaces
kubectl top nodes                    # CPU/RAM per node
kubectl top pods -n apps             # CPU/RAM per pod

# Quick health check
kubectl get pods -n apps | grep -v Running  # Find broken pods
```

## Accessing the UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| **ArgoCD** | http://<ARGOCD_IP> | admin / `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" \| base64 -d` |
| **Grafana** | http://<GRAFANA_IP> | admin / (set during install) |
| **Traefik Dashboard** | http://<TRAEFIK_IP>/dashboard/ | - |

Find current IPs:
```bash
kubectl get svc -A --field-selector spec.type=LoadBalancer \
  -o custom-columns='NAME:.metadata.name,IP:.status.loadBalancer.ingress[0].ip,PORTS:.spec.ports[*].port'
```

## Managing Containers (Pods)

### View all running workloads
```bash
kubectl get pods -n apps -o wide
```

### View logs of a container
```bash
# Last 50 lines
kubectl logs <pod-name> -n apps --tail=50

# Follow logs in real-time
kubectl logs <pod-name> -n apps -f

# Logs of a specific container in a multi-container pod
kubectl logs <pod-name> -n apps -c <container-name>

# Logs from a crashed/restarted container (previous instance)
kubectl logs <pod-name> -n apps --previous
```

### Restart a pod/deployment
```bash
# Graceful restart (rolling update, zero downtime)
kubectl rollout restart deployment <name> -n apps

# Force kill and recreate a specific pod
kubectl delete pod <pod-name> -n apps
# K8s automatically recreates it via the Deployment controller
```

### Exec into a running container
```bash
kubectl exec -it <pod-name> -n apps -- /bin/bash
# or /bin/sh for alpine containers
kubectl exec -it <pod-name> -n apps -- /bin/sh

# Multi-container pod: specify container
kubectl exec -it <pod-name> -n apps -c <container-name> -- /bin/sh
```

### Stop a workload (without deleting)
```bash
# Scale to 0 replicas
kubectl scale deployment <name> -n apps --replicas=0

# Start it again
kubectl scale deployment <name> -n apps --replicas=1
```

---

## Deploying a New Application

### Option A: Quick deploy (kubectl, no GitOps)

For testing or one-off deployments:

```bash
# 1. Create the deployment
kubectl create deployment my-app -n apps \
  --image=nginx:alpine \
  --port=80

# 2. Expose it
kubectl expose deployment my-app -n apps \
  --type=LoadBalancer \
  --port=8080 \
  --target-port=80

# 3. Check the assigned IP
kubectl get svc my-app -n apps
```

### Option B: From a Docker Compose file (recommended)

Step-by-step conversion:

```bash
# 1. Create a directory for your manifests
mkdir -p manifests/apps/my-app/

# 2. For each service in docker-compose.yml, create:
#    - Deployment (replaces the "service" definition)
#    - Service (replaces "ports")
#    - PersistentVolumeClaim (replaces "volumes")
#    - ConfigMap/Secret (replaces "environment" / "env_file")
```

**Template for a typical web app:**

```yaml
# manifests/apps/my-app/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: apps
  labels:
    app.kubernetes.io/name: my-app
spec:
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: my-app
  template:
    metadata:
      labels:
        app.kubernetes.io/name: my-app
    spec:
      enableServiceLinks: false    # Prevents K8s env var conflicts
      containers:
      - name: my-app
        image: my-image:tag
        ports:
        - containerPort: 8080
          name: http
        envFrom:
        - secretRef:
            name: my-app-env       # From: kubectl create secret generic my-app-env --from-env-file=.env
        volumeMounts:
        - name: data
          mountPath: /app/data
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            memory: 512Mi
        livenessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 30
          periodSeconds: 30
        readinessProbe:
          httpGet:
            path: /health
            port: http
          initialDelaySeconds: 10
          periodSeconds: 10
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: my-app-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-app-data
  namespace: apps
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 5Gi
---
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: apps
spec:
  type: LoadBalancer          # Gets an external IP from MetalLB
  ports:
  - port: 8080                # External port
    targetPort: http           # Container port
  selector:
    app.kubernetes.io/name: my-app
```

```bash
# 3. Create the secret from your .env file
kubectl create secret generic my-app-env -n apps --from-env-file=.env

# 4. Deploy
kubectl apply -f manifests/apps/my-app/

# 5. Check status
kubectl get pods -n apps -l app.kubernetes.io/name=my-app
kubectl get svc my-app -n apps
```

### Option C: Using a custom Docker image

```bash
# 1. Build and push to local registry
docker build -t 10.10.0.203:5000/my-app:latest .
docker push 10.10.0.203:5000/my-app:latest

# 2. Reference in your deployment.yaml:
#    image: 10.10.0.203:5000/my-app:latest

# 3. Deploy as above
kubectl apply -f manifests/apps/my-app/
```

### Option D: GitOps (automatic deploy on git push)

```bash
# 1. Add manifests to the Git repo under manifests/apps/my-app/
# 2. Create an ArgoCD Application:
cat > manifests/core/argocd/apps/my-app.yaml <<'EOF'
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<GITHUB_USER>/Ice-Kubernetes.git
    targetRevision: main
    path: manifests/apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: apps
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
EOF

# 3. git add, commit, push → ArgoCD auto-deploys
```

---

## Updating an Application

### Update container image
```bash
# Quick: set new image directly
kubectl set image deployment/my-app my-app=my-image:v2.0 -n apps

# Or: update the image, rebuild, push
docker build -t 10.10.0.203:5000/my-app:v2.0 .
docker push 10.10.0.203:5000/my-app:v2.0
kubectl set image deployment/my-app my-app=10.10.0.203:5000/my-app:v2.0 -n apps

# Or: update manifest and re-apply
kubectl apply -f manifests/apps/my-app/deployment.yaml
```

### Update environment variables
```bash
# Recreate the secret
kubectl create secret generic my-app-env -n apps --from-env-file=.env \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods to pick up new env
kubectl rollout restart deployment my-app -n apps
```

### Rollback
```bash
# View rollout history
kubectl rollout history deployment/my-app -n apps

# Rollback to previous version
kubectl rollout undo deployment/my-app -n apps

# Rollback to specific revision
kubectl rollout undo deployment/my-app -n apps --to-revision=2
```

---

## Running Workloads on Specific Nodes

### Use nodeSelector (simple)
```yaml
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: ki01           # Specific node
        # OR
        node-role.kubernetes.io/worker: ""     # Any worker
        # OR
        gpu: nvidia                            # Any GPU node
```

### Use nodeAffinity (flexible)
```yaml
spec:
  template:
    spec:
      affinity:
        nodeAffinity:
          # MUST run on a worker node
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/worker
                operator: Exists
          # PREFER a node with lots of memory
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 80
            preference:
              matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values: ["kibana-osint"]
```

### Move a running deployment to another node
```bash
# Add nodeSelector to existing deployment
kubectl patch deployment my-app -n apps --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/nodeSelector","value":{"kubernetes.io/hostname":"ki01"}}]'
```

### Available node labels
```bash
kubectl get nodes --show-labels
```

---

## GPU Workloads

### Request GPU in a pod
```yaml
spec:
  containers:
  - name: ml-model
    image: my-model:latest
    resources:
      limits:
        nvidia.com/gpu: 1       # Request 1 GPU
```

### Check GPU availability
```bash
# See GPU resources per node
kubectl describe node ki01 | grep -A5 "Allocated resources"

# Check NVIDIA device plugin
kubectl get pods -n kube-system -l name=nvidia-device-plugin-ds
```

---

## Troubleshooting

### Pod won't start

```bash
# 1. Check pod status and events
kubectl describe pod <pod-name> -n apps

# 2. Common issues:
```

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImagePullBackOff` | Can't pull image (DNS, auth, typo) | Check image name, DNS, registry access |
| `CrashLoopBackOff` | Container starts then crashes | `kubectl logs <pod> --previous` |
| `Pending` | No node can schedule it | `kubectl describe pod` → check Events |
| `CreateContainerConfigError` | Bad env var, missing secret/configmap | `kubectl describe pod` → check mounts |
| `OOMKilled` | Out of memory | Increase `resources.limits.memory` |
| `Evicted` | Node disk pressure | Clean up images: `crictl rmi --prune` |

### Container crashes on startup

```bash
# Check logs from the crashed container
kubectl logs <pod-name> -n apps --previous

# Check if it's a config issue
kubectl describe pod <pod-name> -n apps | grep -A10 "Environment"

# Try running an interactive shell to debug
kubectl run debug --rm -it --image=busybox -- /bin/sh
```

### Service not reachable

```bash
# 1. Is the pod running?
kubectl get pods -n apps -l app.kubernetes.io/name=my-app

# 2. Is the service configured correctly?
kubectl get svc my-app -n apps
kubectl get endpoints my-app -n apps     # Should show pod IP:port

# 3. Test from inside the cluster
kubectl run curl --rm -it --image=curlimages/curl -- curl http://my-app.apps.svc:8080

# 4. Check LoadBalancer IP assigned
kubectl get svc my-app -n apps -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### Node not Ready

```bash
# Check node conditions
kubectl describe node <node-name> | grep -A5 Conditions

# Check K3s agent logs on the node
ssh root@<node-ip> "journalctl -u k3s-agent -f"

# Restart K3s agent
ssh root@<node-ip> "systemctl restart k3s-agent"
```

### DNS issues (slow image pulls)

```bash
# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution from a pod
kubectl run dns-test --rm -it --image=busybox -- nslookup registry-1.docker.io

# If Docker Hub is slow, pre-pull images via Docker and import:
docker pull my-image:tag
docker save my-image:tag | k3s ctr images import -
```

---

## Scaling

### Scale a deployment
```bash
# Scale up
kubectl scale deployment my-app -n apps --replicas=3

# Scale down
kubectl scale deployment my-app -n apps --replicas=1

# Auto-scale (based on CPU)
kubectl autoscale deployment my-app -n apps --min=1 --max=5 --cpu-percent=80
```

---

## Storage Management

### List all volumes
```bash
kubectl get pvc -n apps
kubectl get pv
```

### Resize a volume
```bash
# Edit the PVC (if StorageClass allows expansion)
kubectl patch pvc my-app-data -n apps -p '{"spec":{"resources":{"requests":{"storage":"20Gi"}}}}'
```

### Use NFS storage (shared across nodes)
```yaml
spec:
  volumes:
  - name: shared-data
    persistentVolumeClaim:
      claimName: my-shared-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-shared-data
  namespace: apps
spec:
  storageClassName: nfs-synology      # Uses Synology NFS
  accessModes: [ReadWriteMany]        # Multiple pods can access
  resources:
    requests:
      storage: 10Gi
```

---

## Backup and Restore

### Backup a database (PostgreSQL)
```bash
# Run pg_dump inside the pod
kubectl exec <db-pod> -n apps -- pg_dump -U <user> <dbname> > backup.sql

# Or copy files from a PVC
kubectl cp apps/<pod>:/var/lib/postgresql/data ./backup-data/
```

### Restore a database
```bash
# Copy dump into pod
kubectl cp backup.sql apps/<db-pod>:/tmp/backup.sql

# Execute restore
kubectl exec <db-pod> -n apps -- psql -U <user> <dbname> < /tmp/backup.sql
```

### Backup all PVCs
```bash
./scripts/backup-docker-volumes.sh  # The backup script from this repo
```

---

## Adding a New Node

```bash
# 1. On the NEW node (Linux with systemd):
curl -sfL https://get.k3s.io | K3S_URL=https://<SERVER_IP>:6443 \
  K3S_TOKEN=<TOKEN> \
  INSTALL_K3S_EXEC="agent --node-ip <NEW_NODE_IP> --node-name <NAME>" sh -

# 2. Configure local registry access:
mkdir -p /etc/rancher/k3s
cat > /etc/rancher/k3s/registries.yaml <<'EOF'
mirrors:
  "<REGISTRY_IP>:5000":
    endpoint:
      - "http://<REGISTRY_IP>:5000"
EOF
systemctl restart k3s-agent

# 3. Install NFS client:
apt install -y nfs-common

# 4. On the server - label the new node:
kubectl label node <NAME> node-role.kubernetes.io/worker=""

# 5. Verify:
kubectl get nodes
```

Get the token:
```bash
cat /var/lib/rancher/k3s/server/node-token
```

## Removing a Node

```bash
# 1. Drain (move all pods off the node)
kubectl drain <node-name> --ignore-daemonsets --delete-emptydir-data

# 2. Remove from cluster
kubectl delete node <node-name>

# 3. On the node itself: uninstall K3s agent
/usr/local/bin/k3s-agent-uninstall.sh
```

---

## Monitoring and Alerts

### Grafana Dashboards

Access Grafana at `http://<GRAFANA_IP>` and use these dashboards:

| Dashboard | ID | Shows |
|-----------|-----|-------|
| Node Exporter Full | 1860 | CPU, RAM, Disk, Network per node |
| K8s Cluster Overview | 7249 | Cluster health at a glance |
| K8s Pods | 6336 | Resource usage per pod |

### Prometheus Queries (useful)

```promql
# Node CPU usage %
100 - (avg by(instance)(irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)

# Node RAM usage %
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# Pod memory usage
container_memory_working_set_bytes{namespace="apps"}

# Disk space remaining
node_filesystem_avail_bytes{fstype!="tmpfs"}
```

### Set up alerts in Grafana

1. Go to Alerting → Alert rules → New alert rule
2. Define condition (e.g., RAM > 90% for 5 min)
3. Add notification channel (email, Slack, webhook)

---

## GitOps Workflow

### Daily workflow

```
1. Edit manifests locally (or in GitHub UI)
2. git add, commit, push
3. ArgoCD detects change (within ~3 minutes)
4. ArgoCD applies changes to cluster
5. Verify in ArgoCD UI or: kubectl get pods -n apps
```

### Check ArgoCD sync status
```bash
# Via kubectl
kubectl get applications -n argocd

# Via ArgoCD CLI
argocd app list
argocd app get <app-name>

# Force sync
argocd app sync <app-name>
```

### ArgoCD shows "OutOfSync"

This means the Git repo and cluster state differ. Common causes:
- Manual `kubectl` changes not committed to Git
- ArgoCD detected a drift

Fix: Either sync (apply Git state) or commit your changes to Git.

---

## Common kubectl Commands

```bash
# --- VIEWING ---
kubectl get pods -n apps                    # List pods
kubectl get pods -A                         # All namespaces
kubectl get svc -n apps                     # List services
kubectl get events -n apps --sort-by='.lastTimestamp'  # Recent events
kubectl describe pod <name> -n apps         # Full pod details
kubectl top pods -n apps                    # Resource usage

# --- MODIFYING ---
kubectl apply -f manifest.yaml              # Create/update resources
kubectl delete -f manifest.yaml             # Delete resources
kubectl edit deployment <name> -n apps      # Edit live (vi)
kubectl patch deployment <name> -n apps ... # Patch specific fields

# --- DEBUGGING ---
kubectl logs <pod> -n apps -f               # Stream logs
kubectl exec -it <pod> -n apps -- sh        # Shell into pod
kubectl port-forward svc/<name> -n apps 8080:80  # Local port forward
kubectl run debug --rm -it --image=nicolaka/netshoot -- bash  # Network debug

# --- CLUSTER ---
kubectl get nodes -o wide                   # Node info
kubectl cordon <node>                       # Mark unschedulable
kubectl uncordon <node>                     # Allow scheduling again
kubectl drain <node> --ignore-daemonsets    # Move pods off node
```

---

## Emergency Procedures

### All pods crashing on a node

```bash
# 1. Check node status
kubectl describe node <name>

# 2. SSH to the node and check
ssh root@<ip> "journalctl -u k3s-agent --since '10 min ago'"
ssh root@<ip> "df -h"      # Disk full?
ssh root@<ip> "free -h"    # RAM exhausted?

# 3. If disk full, clean up container images
ssh root@<ip> "k3s crictl rmi --prune"
```

### K3s server (NUC-HA) is down

```bash
# Agent nodes will keep running existing pods
# But no new scheduling or API access until server is back

# Restart K3s server
systemctl restart k3s

# Check status
systemctl status k3s
journalctl -u k3s -f
```

### Need to roll back everything

```bash
# ArgoCD: revert Git commit, ArgoCD auto-syncs to previous state
git revert HEAD
git push

# Manual: rollback specific deployment
kubectl rollout undo deployment/<name> -n apps
```

### Complete cluster reset (last resort)

```bash
# On each AGENT node:
/usr/local/bin/k3s-agent-uninstall.sh

# On the SERVER node:
/usr/local/bin/k3s-uninstall.sh
# WARNING: This deletes all cluster data!
```
