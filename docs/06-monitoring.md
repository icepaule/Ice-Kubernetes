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

## Network Backbone Monitoring (smokeping_prober + iperf3)

App: `manifests/apps/network-monitoring/` (ArgoCD app `network-monitoring`, namespace `monitoring`).

Latency/loss trending and real throughput testing for the physical network backbone
(switches, router/firewall, key hosts) - independent of whether those hosts run K8s workloads.

| Component | What | Where |
|-----------|------|-------|
| `smokeping-prober` (DaemonSet) | ICMP ping loop (5s interval) against 9 backbone targets (CRS305, sw-az, sw-keller-Cisco-Switches, pfSense, USG, NUC-HA, ki02, synnas, prox2), exports Prometheus histograms | Both K3s nodes, `hostNetwork: true` |
| `iperf3-server` (Deployment) | iperf3 server, permanently listening | Pinned to `ki02` |
| `iperf3-exporter` (Deployment) | Blackbox-style exporter (`edgard/iperf3_exporter`); Prometheus calls `/probe?target=<ip>`, which triggers a real iperf3 client run and returns the result synchronously | Pinned to `nuc-ha` (so the test traffic actually crosses the CRS305 backbone instead of staying node-local) |

Both are wired into Prometheus via Prometheus-Operator CRDs (`PodMonitor` for smokeping,
`Probe` for iperf3 - no manual `scrape_configs` needed) and ship their own Grafana
dashboards ("Smokeping", "iperf3 Backbone Throughput") auto-loaded via the existing
`grafana_dashboard: "1"` ConfigMap-sidecar convention.

`hostNetwork: true` is deliberate on all three workloads: it measures the real physical
link, not the CNI overlay. `smokeping_prober` needs `NET_RAW` for raw ICMP sockets. The
iperf3 probe interval is 5 minutes (it briefly saturates the link, ~930 Mbit/s on a
1GbE backbone) - do not lower it without considering the bandwidth impact.

To add more targets: edit `configmap-smokeping-targets.yaml` (plain IP, no DNS
dependency on purpose - the monitor shouldn't rely on the thing it might need to
alert about) or `probe-iperf3.yaml` (needs a matching `iperf3-server` on the new
target host).

## Next Step

Proceed to [07 - GitOps with ArgoCD](07-gitops-argocd.md).
