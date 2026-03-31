# 06 - Monitoring

Monitoring K3s cluster nodes, pods, and external Docker hosts with Prometheus and Grafana.

## Architecture

```
+------------------+     +------------------+     +------------------+
| K3s Nodes        |     | Synology (Docker)|     | ESXi VMs         |
| (auto-discovered)|     | node-exporter    |     | node-exporter    |
|                  |     | cAdvisor         |     |                  |
+--------+---------+     +--------+---------+     +--------+---------+
         |                        |                        |
         +------------------------+------------------------+
                                  |
                        +---------v----------+
                        |    Prometheus      |
                        | (kube-prometheus-  |
                        |  stack)            |
                        +---------+----------+
                                  |
                        +---------v----------+
                        |     Grafana        |
                        | - K8s Dashboards   |
                        | - Docker Hosts     |
                        | - Node Metrics     |
                        +--------------------+
```

## K3s Cluster Monitoring (Automatic)

The kube-prometheus-stack automatically monitors:
- All K3s nodes (CPU, RAM, disk, network)
- All pods and containers
- Kubernetes API server, etcd, scheduler
- CoreDNS, Traefik ingress

No additional configuration needed for in-cluster resources.

## External Docker Host Monitoring

### Deploy node-exporter + cAdvisor on Docker hosts

On each **external Docker host** (e.g., Synology NAS):

```yaml
# docker-compose.monitoring.yml
services:
  node-exporter:
    image: prom/node-exporter:latest
    container_name: node-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    volumes:
      - /proc:/host/proc:ro
      - /sys:/host/sys:ro
      - /:/rootfs:ro
    command:
      - '--path.procfs=/host/proc'
      - '--path.sysfs=/host/sys'
      - '--path.rootfs=/rootfs'
      - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'

  cadvisor:
    image: gcr.io/cadvisor/cadvisor:latest
    container_name: cadvisor
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker/:/var/lib/docker:ro
    privileged: true
```

```bash
docker compose -f docker-compose.monitoring.yml up -d
```

### Configure Prometheus scrape targets

Add external targets in `helm-values/monitoring-values.yaml`:

```yaml
prometheus:
  prometheusSpec:
    additionalScrapeConfigs:
    - job_name: 'external-node-exporter'
      static_configs:
      - targets:
        - '<DOCKER_HOST_1>:9100'
        - '<DOCKER_HOST_2>:9100'
        labels:
          source: external
    - job_name: 'external-cadvisor'
      static_configs:
      - targets:
        - '<DOCKER_HOST_1>:8080'
        labels:
          source: external
```

## Grafana Dashboards

Recommended dashboards (import by ID):

| Dashboard | ID | Purpose |
|-----------|-----|---------|
| Node Exporter Full | 1860 | System metrics per node |
| K8s Cluster Overview | 7249 | Kubernetes cluster health |
| K8s Pods | 6336 | Per-pod resource usage |
| Docker Container Monitoring | 893 | cAdvisor container metrics |
| Traefik | 4475 | Ingress metrics |
| ArgoCD | 14584 | GitOps sync status |

## Alerting

Configure alerting rules in `helm-values/monitoring-values.yaml`:

```yaml
additionalPrometheusRulesMap:
  custom-rules:
    groups:
    - name: node-alerts
      rules:
      - alert: HighMemoryUsage
        expr: (1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) > 0.9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
      - alert: DiskSpaceLow
        expr: (1 - node_filesystem_avail_bytes{fstype!="tmpfs"} / node_filesystem_size_bytes) > 0.85
        for: 10m
        labels:
          severity: warning
```

## Next Step

Proceed to [07 - GitOps with ArgoCD](07-gitops-argocd.md).
