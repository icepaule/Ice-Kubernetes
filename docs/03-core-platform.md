# 03 - Core Platform

After K3s is running, deploy the core platform components.

## Step 1: Create Namespaces

```bash
kubectl apply -f manifests/namespaces.yaml
```

## Step 2: MetalLB (LoadBalancer)

MetalLB provides LoadBalancer-type services on bare-metal clusters.

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
helm install metallb metallb/metallb -n metallb-system --create-namespace \
  -f helm-values/metallb-values.yaml
```

After MetalLB pods are running, apply the IP address pool:
```bash
kubectl apply -f manifests/core/metallb/ip-pool.yaml
```

## Step 3: NFS Storage Provisioner

Provides dynamic PersistentVolume provisioning via NFS.

### Prerequisites
- NFS server with an export (e.g., `/volume2/k3s-data`)
- NFS client tools on all K3s nodes: `apt install -y nfs-common`

```bash
helm repo add nfs-subdir https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner
helm repo update
helm install nfs-provisioner nfs-subdir/nfs-subdir-external-provisioner \
  -n kube-system \
  -f helm-values/nfs-provisioner-values.yaml
```

Verify the StorageClass:
```bash
kubectl get storageclass
# Expected: nfs-synology (or your chosen name)
```

## Step 4: Prometheus + Grafana (Monitoring)

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f helm-values/monitoring-values.yaml
```

Access Grafana:
```bash
# Get the Grafana service IP
kubectl get svc -n monitoring monitoring-grafana

# Default credentials (change in helm-values):
# User: admin
# Password: <set in monitoring-values.yaml>
```

## Step 5: ArgoCD (GitOps)

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace \
  -f helm-values/argocd-values.yaml
```

### Get ArgoCD admin password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

### Connect GitHub Repository
```bash
# Via CLI
argocd repo add https://github.com/<GITHUB_USER>/Ice-Kubernetes.git

# Or via ArgoCD UI (recommended)
```

### Deploy App-of-Apps
```bash
kubectl apply -f manifests/core/argocd/app-of-apps.yaml
```

## Verification

```bash
# All core pods running?
kubectl get pods -A

# MetalLB ready?
kubectl get pods -n metallb-system

# Monitoring running?
kubectl get pods -n monitoring

# ArgoCD healthy?
kubectl get pods -n argocd

# Storage class available?
kubectl get storageclass
```

## Next Step

Proceed to [04 - Workload Migration](04-workload-migration.md).
