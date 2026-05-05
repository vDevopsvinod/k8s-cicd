#!/bin/bash
set -e

# 🔴 REMOVE old Kubernetes repo (important)
sudo rm -f /etc/apt/sources.list.d/kubernetes.list*
sudo rm -f /etc/apt/keyrings/kubernetes-archive-keyring.gpg
sudo sed -i '/apt.kubernetes.io/d' /etc/apt/sources.list || true

# 🔹 Update system
sudo apt-get clean
sudo apt-get update -y

# 🔹 Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# 🔹 Disable swap
sudo swapoff -a

# 🔹 Enable kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 🔹 Install dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 🔹 Add NEW Kubernetes repo
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
| sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

# 🔹 Install Kubernetes
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# 🔹 Join cluster
sudo bash /home/ubuntu/join.sh