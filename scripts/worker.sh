#!/bin/bash

set -e

sudo apt-get update -y
sudo apt-get install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

sudo swapoff -a

sudo apt-get install -y apt-transport-https ca-certificates curl gpg

sudo mkdir -p /etc/apt/keyrings

curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
| sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" \
| sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl

# 🔹 Join cluster
sudo bash /home/ubuntu/join.sh