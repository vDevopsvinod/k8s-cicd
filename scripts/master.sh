#!/bin/bash

set -e

# 🔹 Update system
sudo apt-get update -y

# 🔹 Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# 🔹 Disable swap
sudo swapoff -a

# 🔹 Enable required kernel modules
sudo modprobe overlay
sudo modprobe br_netfilter

echo "net.bridge.bridge-nf-call-iptables = 1" | sudo tee /etc/sysctl.d/k8s.conf
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl --system

# 🔹 Install dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 🔹 Add NEW Kubernetes repo (correct one)
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
| sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

# 🔹 Install Kubernetes
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# 🔹 Initialize cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 | tee /home/ubuntu/init.txt

# 🔹 Configure kubectl
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# 🔹 Allow pods on master
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

# 🔹 Install network (Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# 🔹 Generate join command
grep "kubeadm join" /home/ubuntu/init.txt > /home/ubuntu/join.sh
chmod +x /home/ubuntu/join.sh