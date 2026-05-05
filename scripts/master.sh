#!/bin/bash
set -e

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive
export GPG_TTY=/dev/null

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

## 1. Clean environment
log_info "Cleaning previous Kubernetes configurations..."
sudo rm -f /etc/apt/sources.list.d/kubernetes* /etc/apt/keyrings/kubernetes-apt-keyring.gpg 2>/dev/null || true
sudo sed -i '/apt.kubernetes.io/d' /etc/apt/sources.list 2>/dev/null || true

## 2. Disable Swap (Required for K8s)
log_info "Disabling swap..."
sudo swapoff -a 2>/dev/null || log_warn "Swap already disabled"
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

## 3. Kernel Modules & Networking
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

## 4. Install Containerd
log_info "Installing containerd..."
sudo apt-get update > /dev/null 2>&1
sudo apt-get install -y containerd > /dev/null 2>&1

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

## 5. Install Kubernetes Components - FIX: Separate curl and gpg operations
log_info "Installing Kubernetes components..."
sudo apt-get install -y apt-transport-https ca-certificates curl gpg > /dev/null 2>&1
sudo mkdir -p -m 755 /etc/apt/keyrings

# FIX: Download key to temporary file first, then convert with gpg
log_info "Downloading Kubernetes GPG key..."
MAX_RETRIES=3
RETRY_COUNT=0
TEMP_KEY="/tmp/k8s-release.key"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -fsSL --max-time 30 --output "$TEMP_KEY" \
        https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key 2>/dev/null; then
        
        # Verify file was downloaded
        if [ -s "$TEMP_KEY" ]; then
            log_info "GPG key downloaded successfully"
            break
        else
            log_warn "Downloaded file is empty"
            RETRY_COUNT=$((RETRY_COUNT + 1))
        fi
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

# Now convert the key with gpg (no pipe, no tty issues)
log_info "Converting GPG key format..."
if sudo gpg --dearmor --yes --batch --no-tty --quiet \
    --output /etc/apt/keyrings/kubernetes-apt-keyring.gpg "$TEMP_KEY" 2>/dev/null; then
    log_info "GPG key processed successfully"
    rm -f "$TEMP_KEY"
else
    log_error "Failed to process GPG key"
    exit 1
fi

# Verify the key exists and has content
if [ ! -s /etc/apt/keyrings/kubernetes-apt-keyring.gpg ]; then
    log_error "GPG key file is empty or missing"
    exit 1
fi

# Add Kubernetes repository
log_info "Adding Kubernetes repository..."
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
sudo tee /etc/apt/sources.list.d/kubernetes.list > /dev/null

sudo apt-get update > /dev/null 2>&1
log_info "Installing kubelet, kubeadm, and kubectl..."
sudo apt-get install -y kubelet kubeadm kubectl > /dev/null 2>&1
sudo apt-mark hold kubelet kubeadm kubectl > /dev/null 2>&1

## 6. Initialize Cluster
log_info "Initializing Kubernetes cluster..."
log_info "This may take 2-3 minutes..."
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 2>&1 | tee $HOME/init.txt

## 7. Setup Local Kubeconfig
log_info "Setting up kubeconfig..."
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

## 8. Install Calico Networking
log_info "Installing Calico CNI plugin..."
if kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml > /dev/null 2>&1; then
    log_info "Calico installed successfully"
else
    log_error "Failed to install Calico. Check your internet connection."
    exit 1
fi

## 9. Create Join Script for Workers
log_info "Creating worker join script..."
if grep -A 2 "kubeadm join" $HOME/init.txt > $HOME/join.sh; then
    chmod +x $HOME/join.sh
    log_info "Join command saved to: ~/join.sh"
else
    log_error "Failed to extract join command. Check kubeadm init output."
    exit 1
fi

echo ""
echo "========================================"
log_info "Master node setup completed!"
echo "========================================"
echo ""
echo "Next steps:"
echo "1. Wait for nodes to be ready: kubectl get nodes"
echo "2. Wait for pods to be running: kubectl get pods -A"
echo "3. Copy join.sh to worker nodes and run it"
echo ""
