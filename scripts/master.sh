#!/bin/bash

set -e

# 🔹 Update system
sudo apt-get update -y

# 🔹 Install Docker
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

# 🔹 Disable swap (required for kubeadm)
sudo swapoff -a

# 🔹 Install dependencies
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# 🔹 FIX: New Kubernetes repo method (NO apt-key)
sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
| sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
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

# 🔹 Install Calico network
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# 🔹 Generate join command (clean)
grep "kubeadm join" /home/ubuntu/init.txt > /home/ubuntu/join.sh
chmod +x /home/ubuntu/join.sh