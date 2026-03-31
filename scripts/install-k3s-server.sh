#!/bin/bash
# Install K3s Server Node
# Usage: ./install-k3s-server.sh
#
# Prerequisites:
#   - Root access
#   - curl installed
#   - Network interface configured with static IP
#
# Configuration: Edit the variables below before running.

set -euo pipefail

# === CONFIGURATION ===
SERVER_IP="${K3S_SERVER_IP:?Set K3S_SERVER_IP}"
BIND_INTERFACE="${K3S_BIND_INTERFACE:?Set K3S_BIND_INTERFACE}"
EXTERNAL_IP="${K3S_EXTERNAL_IP:-}"      # Optional: additional TLS SAN
CLUSTER_CIDR="${K3S_CLUSTER_CIDR:-10.42.0.0/16}"
SERVICE_CIDR="${K3S_SERVICE_CIDR:-10.43.0.0/16}"
# === END CONFIGURATION ===

echo "=== K3s Server Installation ==="
echo "Server IP:      $SERVER_IP"
echo "Interface:      $BIND_INTERFACE"
echo "Cluster CIDR:   $CLUSTER_CIDR"
echo "Service CIDR:   $SERVICE_CIDR"
echo ""

# Pre-flight checks
echo "[1/5] Running pre-flight checks..."

if ! ip link show "$BIND_INTERFACE" &>/dev/null; then
    echo "ERROR: Interface $BIND_INTERFACE not found"
    exit 1
fi

if ss -tlnp | grep -q ':6443 '; then
    echo "ERROR: Port 6443 is already in use"
    exit 1
fi

if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    echo "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-k3s.conf
fi

echo "  Pre-flight checks passed."

# Build TLS SAN arguments
TLS_SANS="--tls-san $SERVER_IP --tls-san k3s.local"
if [ -n "$EXTERNAL_IP" ]; then
    TLS_SANS="$TLS_SANS --tls-san $EXTERNAL_IP"
fi

# Install K3s
echo "[2/5] Installing K3s server..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="server \
  --bind-address $SERVER_IP \
  --advertise-address $SERVER_IP \
  --node-ip $SERVER_IP \
  $TLS_SANS \
  --flannel-iface $BIND_INTERFACE \
  --write-kubeconfig-mode 644 \
  --disable servicelb \
  --cluster-cidr $CLUSTER_CIDR \
  --service-cidr $SERVICE_CIDR" sh -

# Wait for K3s to be ready
echo "[3/5] Waiting for K3s to be ready..."
sleep 10
timeout 120 bash -c 'until kubectl get nodes &>/dev/null; do sleep 5; done'

# Install Helm
echo "[4/5] Installing Helm..."
if ! command -v helm &>/dev/null; then
    curl -sfL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
else
    echo "  Helm already installed."
fi

# Verify
echo "[5/5] Verifying installation..."
echo ""
echo "=== Node Status ==="
kubectl get nodes -o wide
echo ""
echo "=== System Pods ==="
kubectl get pods -A
echo ""
echo "=== Node Token (save securely!) ==="
cat /var/lib/rancher/k3s/server/node-token
echo ""
echo "=== Kubeconfig ==="
echo "  /etc/rancher/k3s/k3s.yaml"
echo ""
echo "K3s server installation complete!"
