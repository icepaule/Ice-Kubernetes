# 07 - GitOps with ArgoCD

ArgoCD continuously syncs your Git repository to the K3s cluster. Push a manifest change to GitHub, and ArgoCD automatically deploys it.

## Architecture

```
Developer pushes to GitHub
         |
         v
  GitHub Repository
  (Ice-Kubernetes)
         |
    ArgoCD watches
         |
         v
  K3s Cluster applies
  manifests automatically
```

## App-of-Apps Pattern

We use the **App-of-Apps** pattern: one root ArgoCD Application manages all other Applications.

```
argocd/app-of-apps.yaml
    ├── apps/stock-analyzer (ArgoCD Application)
    ├── apps/searxng (ArgoCD Application)
    ├── apps/xwiki (ArgoCD Application)
    └── ... (one per stack)
```

## Connect GitHub Repository

### Option 1: Via ArgoCD UI
1. Open ArgoCD UI (https://<ARGOCD_IP> or via ingress)
2. Settings > Repositories > Connect Repo
3. Enter: `https://github.com/<GITHUB_USER>/Ice-Kubernetes.git`
4. For private repos: add a GitHub PAT or deploy key

### Option 2: Via CLI
```bash
# Install ArgoCD CLI
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && mv argocd /usr/local/bin/

# Login
argocd login <ARGOCD_IP> --username admin --password <PASSWORD>

# Add repo
argocd repo add https://github.com/<GITHUB_USER>/Ice-Kubernetes.git
```

## Deploy the App-of-Apps

```bash
kubectl apply -f manifests/core/argocd/app-of-apps.yaml
```

This creates a root Application that watches the `manifests/apps/` directory. For each subdirectory, add an ArgoCD Application manifest.

## Adding a New Workload

1. Create manifests in `manifests/apps/<app-name>/`
2. Create an ArgoCD Application in `manifests/core/argocd/apps/<app-name>.yaml`
3. Commit and push to GitHub
4. ArgoCD auto-syncs and deploys

## Workflow Example

```bash
# Make a change (e.g., update image tag)
vim manifests/apps/stock-analyzer/deployment.yaml

# Commit and push
git add -A
git commit -m "Update stock-analyzer to v2.0"
git push

# ArgoCD detects the change and syncs automatically
# Check status:
argocd app get stock-analyzer
```

## Sync Policies

| Policy | Behavior |
|--------|----------|
| `automated.prune` | Deletes K8s resources removed from Git |
| `automated.selfHeal` | Re-applies manifests if cluster state drifts |
| Manual sync | Requires clicking "Sync" in UI (safer for production) |

## GitHub Actions Integration (Optional)

Automate container builds when Dockerfiles change:

```yaml
# .github/workflows/build-images.yml
name: Build & Push Images
on:
  push:
    paths:
      - 'images/**'

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - uses: docker/login-action@v3
      with:
        registry: ghcr.io
        username: ${{ github.actor }}
        password: ${{ secrets.GITHUB_TOKEN }}

    - uses: docker/build-push-action@v6
      with:
        context: images/<app-name>
        push: true
        tags: ghcr.io/${{ github.repository_owner }}/<app-name>:${{ github.sha }}
```

## Secrets Management

**Never store secrets in Git!** Use one of:

1. **Kubernetes Secrets** (created manually):
   ```bash
   kubectl create secret generic <name> \
     --from-literal=key=value -n apps
   ```

2. **Sealed Secrets** (encrypted in Git):
   ```bash
   # Install sealed-secrets controller
   helm install sealed-secrets bitnami-labs/sealed-secrets -n kube-system

   # Encrypt a secret
   kubeseal --format yaml < secret.yaml > sealed-secret.yaml
   # sealed-secret.yaml is safe to commit
   ```

3. **External Secrets Operator** (for Vault, AWS SM, etc.)
