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
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Cleanup on failure
cleanup() {
  local exit_code=$?
  [[ $exit_code -eq 0 ]] || log_error "Setup failed (exit $exit_code). Check logs above."
}
trap cleanup EXIT

###############################################################################
# 1. DISABLE SWAP (idempotent)
###############################################################################
log_info "Disabling swap..."
sudo swapoff -a 2>/dev/null || true
if grep -q "^[^#]*\bswap\b" /etc/fstab 2>/dev/null; then
  sudo sed -i '/^[^#]*\bswap\b/ s/^/#/' /etc/fstab
  log_info "Swap entries commented in /etc/fstab"
fi

###############################################################################
# 2. KERNEL MODULES & NETWORKING
###############################################################################
log_info "Configuring kernel modules..."
sudo mkdir -p /etc/modules-load.d
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF

for mod in overlay br_netfilter; do
  if ! lsmod | grep -q "^${mod}"; then
    sudo modprobe "$mod"
    log_info "Loaded kernel module: $mod"
  fi
done

log_info "Setting sysctl parameters..."
sudo mkdir -p /etc/sysctl.d
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system >/dev/null 2>&1 || true

###############################################################################
# 3. INSTALL & CONFIGURE CONTAINERD
###############################################################################
log_info "Installing containerd..."
sudo apt-get update -qq
sudo apt-get install -y -qq containerd

sudo mkdir -p /etc/containerd
# Generate config only if missing
if [[ ! -f /etc/containerd/config.toml ]]; then
  containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi
# Enable systemd cgroup driver (required for kubelet)
if grep -q "SystemdCgroup = false" /etc/containerd/config.toml; then
  sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  log_info "Enabled systemd cgroup driver in containerd"
fi

sudo systemctl daemon-reload
sudo systemctl enable --now containerd >/dev/null 2>&1
if ! systemctl is-active --quiet containerd; then
  log_error "containerd failed to start"
  exit 1
fi
log_info "containerd installed and running"

###############################################################################
# 4. INSTALL KUBERNETES COMPONENTS (modern keyring method)
###############################################################################
log_info "Installing Kubernetes packages..."
sudo apt-get install -y -qq apt-transport-https ca-certificates curl gpg

# Prepare keyring directory
sudo mkdir -p -m 755 /etc/apt/keyrings

# Download and process GPG key (ASCII-armored → binary)
KEYRING="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
KEY_URL="https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key"
TEMP_KEY="/tmp/k8s-release-key.asc"

log_info "Downloading Kubernetes GPG key..."
for attempt in {1..3}; do
  if curl -fsSL -o "$TEMP_KEY" "$KEY_URL" 2>/dev/null && [[ -s "$TEMP_KEY" ]]; then
    log_info "Key downloaded (${TEMP_KEY})"
    if sudo gpg --dearmor --batch --yes -o "$KEYRING" "$TEMP_KEY" 2>/dev/null && [[ -s "$KEYRING" ]]; then
      log_info "GPG key installed: $KEYRING"
      rm -f "$TEMP_KEY"
      break
    else
      log_error "Failed to dearmor GPG key (attempt $attempt)"
    fi
  else
    log_warn "Failed to download key (attempt $attempt/3)"
  fi
  
  [[ $attempt -eq 3 ]] && { log_error "GPG key setup failed after 3 attempts"; exit 1; }
  sleep 5
done
rm -f "$TEMP_KEY" 2>/dev/null || true

# Add APT repository
log_info "Adding Kubernetes APT repository..."
echo "deb [signed-by=${KEYRING}] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

sudo apt-get update -qq
sudo apt-get install -y -qq kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl >/dev/null
log_info "Kubernetes packages installed and held"

###############################################################################
# 5. INITIALIZE CONTROL-PLANE (if not already done)
###############################################################################
log_info "Checking Kubernetes control-plane status..."
if ! sudo kubeadm token list >/dev/null 2>&1; then
  log_info "Initializing Kubernetes cluster..."
  sudo kubeadm init \
    --pod-network-cidr=10.244.0.0/16 \
    --skip-token-print \
    --v=0 2>/dev/null || {
      log_warn "kubeadm init failed (may already be initialized)"
    }
fi

# Save join command for workers
if sudo kubeadm token create --print-join-command >/dev/null 2>&1; then
  sudo kubeadm token create --print-join-command > "$HOME/join.sh" 2>/dev/null || true
  chmod +x "$HOME/join.sh" 2>/dev/null || true
  log_info "Worker join command saved to: $HOME/join.sh"
fi

# Configure kubectl for current user
mkdir -p "$HOME/.kube"
if [[ -f /etc/kubernetes/admin.conf ]]; then
  sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
  sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
  chmod 600 "$HOME/.kube/config"
  log_info "kubectl configured for user $(whoami)"
fi

###############################################################################
# FINAL OUTPUT
###############################################################################
echo ""
echo "================================================"
log_info "✅ MASTER NODE SETUP COMPLETED"
echo "================================================"
echo ""
echo "NEXT STEPS:"
echo "1️⃣  Install CNI plugin (required for pod networking):"
echo "    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml"
echo ""
echo "2️⃣  On each worker node:"
echo "    • Run ./worker.sh"
echo "    • Then execute the join command from:"
echo "      cat $HOME/join.sh"
echo ""
echo "3️⃣  Verify cluster:"
echo "    kubectl get nodes"
echo "    kubectl get pods -A"
echo ""
echo "TROUBLESHOOTING:"
echo "• Logs: journalctl -u kubelet -f"
echo "• Reset: sudo kubeadm reset -f && sudo rm -rf /etc/cni /etc/kubernetes /var/lib/kubelet /var/lib/etcd"
echo "================================================"