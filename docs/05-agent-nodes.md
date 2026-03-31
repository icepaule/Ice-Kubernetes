# 05 - Agent Nodes

Adding worker nodes to expand the K3s cluster.

## Prerequisites per Agent Node

- Linux with systemd, kernel 5.x+ recommended
- cgroup v2 support
- Network access to K3s server on port 6443
- `curl` installed
- NFS client: `apt install -y nfs-common`

## Step 1: Get the Node Token

On the **server node**:
```bash
cat /var/lib/rancher/k3s/server/node-token
```

## Step 2: Install K3s Agent

On each **agent node**:
```bash
curl -sfL https://get.k3s.io | K3S_URL=https://<SERVER_IP>:6443 \
  K3S_TOKEN=<NODE_TOKEN> \
  INSTALL_K3S_EXEC="agent \
    --node-ip <AGENT_IP> \
    --node-name <AGENT_NAME>" sh -
```

## Step 3: Verify

On the **server node**:
```bash
kubectl get nodes
# All nodes should show Ready status
```

## Step 4: Label Nodes

```bash
# Label by role
kubectl label node <server-name> node-role.kubernetes.io/server=""
kubectl label node <agent-name> node-role.kubernetes.io/worker=""

# Label by capability (e.g., GPU)
kubectl label node <gpu-agent> gpu=nvidia

# Label by location
kubectl label node <agent-name> location=<location>
```

## GPU Agent Node (NVIDIA)

For nodes with NVIDIA GPUs:

### Install NVIDIA Container Toolkit
```bash
# On the agent node
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt update && apt install -y nvidia-container-toolkit

# Configure containerd for NVIDIA
nvidia-ctk runtime configure --runtime=containerd
systemctl restart k3s-agent
```

### Install NVIDIA Device Plugin for K8s
On the **server node**:
```bash
kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.0/deployments/static/nvidia-device-plugin.yml
```

### Using GPU in Pods
```yaml
spec:
  containers:
  - name: ml-workload
    image: your-image
    resources:
      limits:
        nvidia.com/gpu: 1
  nodeSelector:
    gpu: nvidia
```

## Scheduling Workloads to Specific Nodes

Use `nodeSelector` or `nodeAffinity` in your manifests:

```yaml
# Simple: nodeSelector
spec:
  nodeSelector:
    node-role.kubernetes.io/worker: ""

# Advanced: nodeAffinity
spec:
  affinity:
    nodeAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 80
        preference:
          matchExpressions:
          - key: gpu
            operator: In
            values: ["nvidia"]
```

## Next Step

Proceed to [06 - Monitoring](06-monitoring.md).
