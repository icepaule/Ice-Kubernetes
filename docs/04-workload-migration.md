# 04 - Workload Migration

Step-by-step guide for migrating Docker Compose stacks to Kubernetes manifests.

## General Migration Pattern

For each Docker Compose stack:

1. **Analyze** the docker-compose.yml (services, volumes, networks, env vars)
2. **Create K8s manifests**: Deployment, Service, PVC, ConfigMap, Secret
3. **Build & push** custom images to GitHub Container Registry (ghcr.io)
4. **Backup** existing data (volumes, databases)
5. **Deploy** to K3s and verify
6. **Stop** the old Docker stack
7. **Create ArgoCD Application** for GitOps

## Docker Compose to Kubernetes Mapping

| Docker Compose | Kubernetes |
|---------------|-----------|
| `service` | `Deployment` + `Service` |
| `ports` | `Service` (ClusterIP/LoadBalancer/NodePort) |
| `volumes` (named) | `PersistentVolumeClaim` |
| `volumes` (bind mount) | `hostPath` or `ConfigMap` |
| `environment` | `ConfigMap` + `Secret` |
| `depends_on` | `initContainers` or readiness probes |
| `networks` | K8s namespace isolation (or NetworkPolicy) |
| `restart: always` | Default in K8s (restartPolicy: Always) |
| `healthcheck` | `livenessProbe` / `readinessProbe` |

## Migration Order

### 1. Stock Analyzer (Low complexity)

Single container, Flask web app.

```bash
# Backup
docker cp stock-analyzer:/app/data ./backups/stock-analyzer/

# Deploy to K3s
kubectl apply -f manifests/apps/stock-analyzer/

# Verify
kubectl get pods -n apps -l app=stock-analyzer
curl http://<SERVICE_IP>:8501

# Stop old container
docker compose -f /path/to/docker-compose.yml down
```

### 2-5. Simple Stacks (SearXNG, Leak-Monitoring, eBay Assistant, Epstein Research)

Same pattern as above. See individual manifest directories.

### 6. XWiki (Medium complexity)

Multi-container with PostgreSQL database.

```bash
# Backup database FIRST
docker exec xwiki-db pg_dump -U xwiki xwiki > backups/xwiki-db.sql

# Backup XWiki data volume
docker cp xwiki:/usr/local/xwiki/data ./backups/xwiki-data/

# Deploy to K3s (database first, then app)
kubectl apply -f manifests/apps/xwiki/

# Restore database
kubectl cp backups/xwiki-db.sql <xwiki-db-pod>:/tmp/
kubectl exec <xwiki-db-pod> -- psql -U xwiki xwiki < /tmp/xwiki-db.sql

# Verify
kubectl get pods -n apps -l app.kubernetes.io/name=xwiki
```

### 7-8. Cribl/ELK, OpenArchiver (Medium complexity)

Similar pattern with database migrations. Pay attention to:
- Elasticsearch needs `vm.max_map_count=262144`
- MeiliSearch needs significant RAM (~4GB)

### 9. Tax-AI Pipeline (High complexity)

13 containers with complex dependencies. Migration steps:
1. Deploy databases (PostgreSQL, Redis) first
2. Deploy processing services (Tika, Gotenberg)
3. Deploy Paperless-ngx
4. Deploy pipeline workers
5. Deploy web frontends
6. Migrate Paperless data & documents

## Custom Image Builds

For stacks with Dockerfiles, build and push to GitHub Container Registry:

```bash
# Login to ghcr.io
echo "<GITHUB_PAT>" | docker login ghcr.io -u <GITHUB_USER> --password-stdin

# Build and push
docker build -t ghcr.io/<GITHUB_USER>/<image-name>:<tag> .
docker push ghcr.io/<GITHUB_USER>/<image-name>:<tag>

# Update image reference in K8s manifest
```

## Tips

- Always backup data BEFORE stopping the old Docker stack
- Test the K8s deployment thoroughly before removing Docker containers
- Use `kubectl logs <pod>` and `kubectl describe pod <pod>` for debugging
- If a pod won't start, check events: `kubectl get events -n apps --sort-by='.lastTimestamp'`

## Next Step

Proceed to [05 - Agent Nodes](05-agent-nodes.md).
