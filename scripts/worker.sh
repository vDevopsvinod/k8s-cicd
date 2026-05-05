#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# 🔴 Clean ONLY Kubernetes old configs (safe)
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

# 🔹 Disable swap
sudo swapoff -a

# 🔹 Kernel config
sudo modprobe overlay
sudo modprobe br_netfilter

echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 🔹 Dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 🔹 Add Kubernetes repo (modern method)
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key -o /tmp/k8s.key

sudo gpg --dearmor --batch --yes --no-tty \
  -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /tmp/k8s.key

rm -f /tmp/k8s.key

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

# 🔹 Install Kubernetes
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# 🔹 Join cluster
sudo bash /home/ubuntu/join.sh