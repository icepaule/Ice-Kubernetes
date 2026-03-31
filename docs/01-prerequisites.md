# 01 - Prerequisites

## Hardware Requirements

### K3s Server Node (Control Plane)
- **CPU**: 4+ cores recommended
- **RAM**: 8GB minimum, 16GB+ recommended (running workloads on server node)
- **Disk**: 50GB+ free for K3s + container images
- **Network**: Static IP on management network
- **OS**: Debian 12+, Ubuntu 22.04+, or similar Linux with systemd

### K3s Agent Nodes (Workers)
- **CPU**: 2+ cores
- **RAM**: 4GB minimum
- **Disk**: 20GB+ free
- **Network**: Reachable from server node on management network
- **OS**: Linux with systemd, kernel 4.15+ (5.x+ recommended), cgroup v2

### NFS Storage Host
- NFS server with sufficient storage for persistent volumes
- Network reachable from all K3s nodes

## Software Requirements

On the **server node**:
```bash
# Verify cgroup v2
cat /proc/cgroups

# Verify IP forwarding
sysctl net.ipv4.ip_forward
# If not enabled:
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

# Verify required ports are free
ss -tlnp | grep -E ':(6443|10250|8472|51820) '

# Git (for repo management)
apt install -y git

# curl (for K3s installer)
apt install -y curl
```

## Required Ports

### Server Node
| Port | Protocol | Purpose |
|------|----------|---------|
| 6443 | TCP | K3s API Server |
| 10250 | TCP | Kubelet metrics |
| 8472 | UDP | Flannel VXLAN |
| 51820 | UDP | Flannel WireGuard (if enabled) |

### Agent Nodes
| Port | Protocol | Purpose |
|------|----------|---------|
| 10250 | TCP | Kubelet metrics |
| 8472 | UDP | Flannel VXLAN |

## Network Planning

Before installation, plan your IP allocation:

| Resource | CIDR / Range | Purpose |
|----------|-------------|---------|
| Node IPs | Your management network | Physical/VM IPs |
| Cluster CIDR | `10.42.0.0/16` (default) | Pod network |
| Service CIDR | `10.43.0.0/16` (default) | ClusterIP services |
| MetalLB Pool | e.g., `<MGMT_NET>.200-220` | LoadBalancer IPs |

Ensure these CIDRs don't overlap with existing Docker bridge networks (typically `172.17.0.0/16`+) or your physical network.

## Docker Coexistence

If Docker is already running on the server node (e.g., for Home Assistant Supervised):
- K3s uses **containerd** by default (separate from Docker)
- Both runtimes coexist without conflict
- Docker bridge networks (`172.x.x.x`) don't overlap with K3s CIDRs (`10.42.x.x`, `10.43.x.x`)
- Do NOT use the deprecated `--docker` flag for K3s

## Next Step

Proceed to [02 - K3s Server Setup](02-k3s-server-setup.md).
