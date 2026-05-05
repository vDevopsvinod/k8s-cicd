#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Clean old configs
sudo rm -f /etc/apt/sources.list.d/kubernetes* /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo sed -i '/apt.kubernetes.io/d' /etc/apt/sources.list || true

# 1. Install Containerd (The K8s standard runtime)
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

# 2. Disable Swap
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

# 3. Kernel Settings
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

# 4. Install K8s Components
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor --yes --batch -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

# 5. Initialize Cluster
# Use --node-name if your hostname isn't resolvable
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 | tee $HOME/init.txt

# 6. Configure kubectl
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 7. Network Plugin (Calico)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# 8. Create Join Script for Workers
grep -A 2 "kubeadm join" $HOME/init.txt > $HOME/join.sh
chmod +x $HOME/join.sh
echo "Master node ready. Join script created at ~/join.sh"