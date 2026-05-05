#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive
# 🔴 Clean ONLY old Kubernetes configs (safe)
sudo rm -f /etc/apt/sources.list.d/kubernetes*
sudo rm -f /etc/apt/trusted.gpg.d/*kubernetes*
sudo rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 🔴 Remove old repo references
sudo sed -i '/apt.kubernetes.io/d' /etc/apt/sources.list || true

# 🔴 Clean cache
sudo apt-get clean
sudo apt-get update -y

# 🔹 Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# 🔹 Disable swap (required)
sudo swapoff -a

# 🔹 Kernel settings
sudo modprobe overlay
sudo modprobe br_netfilter

echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 🔹 Install dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 🔹 Add Kubernetes repo (modern method)
# 🔹 Add Kubernetes repo (FINAL FIX - NO PIPE)

# 🔹 Add Kubernetes repo (FINAL FIX — NO GPG)

sudo mkdir -p /etc/apt/keyrings

# Just download key (no gpg processing)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | sudo tee /etc/apt/keyrings/kubernetes-apt-keyring.gpg > /dev/null

# Add repo
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

# Remove temp file
rm -f /tmp/k8s.key
# 🔹 Install Kubernetes
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# 🔹 Initialize cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 | tee /home/ubuntu/init.txt

# 🔹 Configure kubectl
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 🔹 Allow pods on master (optional)
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# 🔹 Install Calico network
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# 🔹 Generate join command for worker
grep "kubeadm join" /home/ubuntu/init.txt > /home/ubuntu/join.sh
chmod +x /home/ubuntu/join.sh