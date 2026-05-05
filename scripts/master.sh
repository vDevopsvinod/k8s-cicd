#!/bin/bash
set -euo pipefail

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup trap for partial failures
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    log_error "Setup failed with exit code $exit_code. Check logs above."
  fi
}
trap cleanup EXIT

## 1. Disable Swap (idempotent)
log_info "Disabling swap..."
sudo swapoff -a 2>/dev/null || true
if grep -q "^[^#]*swap" /etc/fstab; then
  sudo sed -i '/^[^#]*swap/ s/^/#/' /etc/fstab
fi

## 2. Kernel Modules & Networking
log_info "Loading kernel modules..."
sudo mkdir -p /etc/modules-load.d
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

for mod in overlay br_netfilter; do
  lsmod | grep -q "$mod" || sudo modprobe "$mod"
done

log_info "Configuring sysctl parameters..."
sudo mkdir -p /etc/sysctl.d
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system >/dev/null 2>&1 || true

## 3. Install & Configure Containerd
log_info "Installing containerd..."
sudo apt-get update -qq
sudo apt-get install -y -qq containerd

sudo mkdir -p /etc/containerd
# Generate default config only if it doesn't exist
if [[ ! -f /etc/containerd/config.toml ]]; then
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi
# Enable systemd cgroup driver (required for Kubernetes)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl enable --now containerd >/dev/null 2>&1
log_info "Containerd installed and running"

## 4. Install Kubernetes Components
log_info "Installing Kubernetes packages..."
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg

# Prepare keyring directory
sudo mkdir -p -m 755 /etc/apt/keyrings

# Download Kubernetes GPG key with retry
KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
KEY_URL="https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key"

log_info "Downloading Kubernetes GPG key..."
for attempt in {1..3}; do
  if sudo curl -fsSL -o "$KEYRING" "$KEY_URL" 2>/dev/null && [[ -s "$KEYRING" ]]; then
    log_info "GPG key downloaded successfully (${KEYRING})"
    break
  elif [[ $attempt -eq 3 ]]; then
    log_error "Failed to download GPG key after 3 attempts"
    exit 1
  else
    log_warn "Attempt $attempt failed, retrying in 5s..."
    sleep 5
  fi
done

# Add Kubernetes repository
log_info "Adding Kubernetes APT repository..."
echo "deb [signed-by=${KEYRING}] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt-get update -qq
sudo apt-get install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null

log_info "Kubernetes components installed and held"

## 5. Generate Join Command (for workers)
log_info "Initializing Kubernetes control-plane..."
if ! sudo kubeadm token list >/dev/null 2>&1; then
  # First-time init - use sensible defaults
  sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --skip-token-print 2>/dev/null || {
    log_warn "kubeadm init failed (may already be initialized)"
  }
fi

# Save join command for workers
if sudo kubeadm token create --print-join-command >/dev/null 2>&1; then
  sudo kubeadm token create --print-join-command > ~/join.sh 2>/dev/null || true
  chmod +x ~/join.sh 2>/dev/null || true
fi

# Setup kubectl for current user
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config" 2>/dev/null || true
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config" 2>/dev/null || true

echo ""
echo "========================================"
log_info "✅ Master node setup completed!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Install a CNI plugin (e.g., Calico):"
echo "   kubectl apply -f https://raw