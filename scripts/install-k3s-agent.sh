#!/bin/bash
# Install K3s Agent Node
# Usage: ./install-k3s-agent.sh
#
# Prerequisites:
#   - Root access
#   - curl installed
#   - Network connectivity to K3s server on port 6443
#
# Configuration: Edit the variables below or set via environment.

set -euo pipefail

# === CONFIGURATION ===
SERVER_URL="${K3S_URL:?Set K3S_URL (e.g., https://<SERVER_IP>:6443)}"
NODE_TOKEN="${K3S_TOKEN:?Set K3S_TOKEN (from server's /var/lib/rancher/k3s/server/node-token)}"
NODE_IP="${K3S_NODE_IP:?Set K3S_NODE_IP}"
NODE_NAME="${K3S_NODE_NAME:-$(hostname)}"
# === END CONFIGURATION ===

echo "=== K3s Agent Installation ==="
echo "Server URL:  $SERVER_URL"
echo "Node IP:     $NODE_IP"
echo "Node Name:   $NODE_NAME"
echo ""

# Pre-flight checks
echo "[1/4] Running pre-flight checks..."

if ! curl -sk --connect-timeout 5 "$SERVER_URL/ping" &>/dev/null; then
    echo "WARNING: Cannot reach K3s server at $SERVER_URL"
    echo "  Make sure the server is running and port 6443 is accessible."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 1
fi

if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    echo "Enabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=1
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.d/99-k3s.conf
fi

# Install NFS client (for NFS-backed PVs)
echo "[2/4] Installing NFS client..."
if command -v apt &>/dev/null; then
    apt install -y nfs-common 2>/dev/null || true
elif command -v yum &>/dev/null; then
    yum install -y nfs-utils 2>/dev/null || true
fi

# Install K3s agent
echo "[3/4] Installing K3s agent..."
curl -sfL https://get.k3s.io | K3S_URL="$SERVER_URL" \
  K3S_TOKEN="$NODE_TOKEN" \
  INSTALL_K3S_EXEC="agent \
    --node-ip $NODE_IP \
    --node-name $NODE_NAME" sh -

# Verify
echo "[4/4] Verifying installation..."
sleep 10

if systemctl is-active --quiet k3s-agent; then
    echo "K3s agent is running."
    echo "Check node status from the server: kubectl get nodes"
else
    echo "WARNING: K3s agent may not be running yet."
    echo "Check logs: journalctl -u k3s-agent -f"
fi

echo ""
echo "K3s agent installation complete!"
echo "Run 'kubectl get nodes' on the server to verify this node joined."
