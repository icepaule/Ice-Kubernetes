# 02 - K3s Server Setup

## Install K3s on the Server Node

### Step 1: Run the K3s installer

```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address <SERVER_IP> \
  --advertise-address <SERVER_IP> \
  --node-ip <SERVER_IP> \
  --tls-san <SERVER_IP> \
  --tls-san <EXTERNAL_IP> \
  --tls-san k3s.local \
  --flannel-iface <INTERFACE> \
  --write-kubeconfig-mode 644 \
  --disable servicelb \
  --cluster-cidr 10.42.0.0/16 \
  --service-cidr 10.43.0.0/16" sh -
```

**Parameter explanation:**
| Parameter | Purpose |
|-----------|---------|
| `--bind-address` | IP K3s API listens on |
| `--advertise-address` | IP advertised to agent nodes |
| `--node-ip` | Node IP for internal communication |
| `--tls-san` | Additional SANs for the TLS certificate |
| `--flannel-iface` | Network interface for Flannel overlay |
| `--write-kubeconfig-mode 644` | Allow non-root kubectl access |
| `--disable servicelb` | Disable built-in LB (we use MetalLB) |

### Step 2: Verify installation

```bash
# Check K3s service
systemctl status k3s

# Check node status
kubectl get nodes
# Expected: NAME    STATUS   ROLES                  AGE   VERSION
#           <name>  Ready    control-plane,master   XXs   v1.xx.x+k3s1

# Check system pods
kubectl get pods -A
# Expected: All pods in Running state
```

### Step 3: Install Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### Step 4: Save the node token (for agent nodes)

```bash
# The token is needed to join agent nodes
cat /var/lib/rancher/k3s/server/node-token
# Save this securely - do NOT commit to git!
```

### Step 5: Configure kubectl (optional, for remote access)

```bash
# Kubeconfig is at:
cat /etc/rancher/k3s/k3s.yaml

# For remote access, copy and adjust the server URL:
# Replace 127.0.0.1 with <SERVER_IP>
```

## Troubleshooting

### K3s won't start
```bash
journalctl -u k3s -f
```

### Port conflict
If port 6443 is in use, K3s will fail. Check with:
```bash
ss -tlnp | grep 6443
```

### Flannel interface issues
If pods can't communicate, verify the flannel interface:
```bash
kubectl -n kube-system logs -l app=flannel
```

## Next Step

Proceed to [03 - Core Platform](03-core-platform.md).
