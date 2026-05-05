#!/bin/bash
set -e

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

# Color output for clarity
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

## 1. Disable Swap
log_info "Disabling swap..."
sudo swapoff -a 2>/dev/null || log_warn "Swap already disabled"
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

## 2. Kernel Modules & Networking
log_info "Loading kernel modules..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf > /dev/null
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

log_info "Configuring kernel parameters..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf > /dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system > /dev/null 2>&1

## 3. Install Containerd
log_info "Installing containerd..."
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y containerd > /dev/null 2>&1

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd
log_info "Containerd installed and configured"

## 4. Install Kubernetes Components
log_info "Installing Kubernetes components..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg > /dev/null 2>&1
sudo mkdir -p -m 755 /etc/apt/keyrings

# Download and add Kubernetes GPG key with retry logic
log_info "Adding Kubernetes GPG key..."
MAX_RETRIES=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -fsSL --max-time 30 https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
       sudo gpg --dearmor --yes --batch -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null; then
        log_info "GPG key added successfully"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            log_warn "Failed to download GPG key (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in 5 seconds..."
            sleep 5
        else
            log_error "Failed to download GPG key after $MAX_RETRIES attempts"
            exit 1
        fi
    fi
done

# Add Kubernetes repository
log_info "Adding Kubernetes repository..."
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt-get update > /dev/null 2>&1
log_info "Installing kubelet, kubeadm, and kubectl..."
sudo apt-get install -y kubelet kubeadm kubectl > /dev/null 2>&1
sudo apt-mark hold kubelet kubeadm kubectl > /dev/null 2>&1

echo ""
echo "========================================"
log_info "Worker node setup completed!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Get the join command from master: cat ~/join.sh"
echo "2. Copy and paste the join command below:"
echo "   (or paste the contents of master's join.sh file)"
echo ""
echo "Example:"
echo "  sudo kubeadm join <master-ip>:6443 --token <token> \\"
echo "    --discovery-token-ca-cert-hash sha256:<hash>"
echo ""
echo "========================================"