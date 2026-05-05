#!/bin/bash

sudo apt update -y
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker

sudo swapoff -a

sudo apt-get install -y apt-transport-https curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -

echo "deb https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update -y
sudo apt install -y kubelet kubeadm kubectl

# Init cluster
sudo kubeadm init --pod-network-cidr=192.168.0.0/16 > /home/ubuntu/init.txt

# Extract join command
grep "kubeadm join" /home/ubuntu/init.txt > /home/ubuntu/join.sh
chmod +x /home/ubuntu/join.sh