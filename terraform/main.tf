provider "aws" {
  region = "us-east-1"
}

# 🔹 Security Group (unique every run → no duplicate error)
resource "aws_security_group" "k8s_sg" {
  name_prefix = "k8s-sg-${timestamp()}-"
  description = "Kubernetes SG"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-sg"
  }
}

# 🔹 Master Node
resource "aws_instance" "master" {
  ami           = "ami-091138d0f0d41ff90"
  instance_type = "t3.small"
  key_name      = "vinod"

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "k8s-master"
  }
}

# 🔹 Worker Node (ONLY 1)
resource "aws_instance" "worker" {
  ami           = "ami-091138d0f0d41ff90"
  instance_type = "t3.small"
  key_name      = "vinod"

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  root_block_device {
    volume_size = 20
  }

  tags = {
    Name = "k8s-worker"
  }
}