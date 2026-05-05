#!/bin/bash
set -e

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

## 1. Clean environment
sudo rm -f /etc/apt/sources.list.d/kubernetes* /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo sed -i '/apt.kubernetes.io/d' /etc/apt/sources.list || true

## 2. Disable Swap (Required for K8s)
sudo swapoff -a
sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

## 3. Kernel Modules & Networking
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

## 4. Install Containerd
sudo apt-get update
sudo apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml
sudo systemctl restart containerd

## 5. Install Kubernetes Components (The GPG Fix)
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings

# The --batch --yes flags solve the /dev/tty error
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | \
sudo gpg --dearmor --yes --batch -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" | \
sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

## 6. Initialize Cluster
# Note: Pod CIDR 192.168.0.0/16 is standard for Calico
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 | tee $HOME/init.txt

## 7. Setup Local Kubeconfig
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

## 8. Install Calico Networking
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

## 9. Create Join Script for Workers
grep -A 2 "kubeadm join" $HOME/init.txt > $HOME/join.sh
chmod +x $HOME/join.sh

echo "----------------------------------------"
echo "Master node is ready!"
echo "Join command saved to: ~/join.sh"
echo "----------------------------------------"