provider "aws" {
  region = "us-east-1"
}

# 🔹 Create NEW Security Group
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg-new-2"
  description = "Allow Kubernetes traffic"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-sg-new-2"
  }
}

# 🔹 Master Node
resource "aws_instance" "master" {
  ami           = "ami-091138d0f0d41ff90"
  instance_type = "t3.micro"
  key_name      = "vinod"

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  tags = {
    Name = "k8s-master"
  }
}

# 🔹 Worker Nodes
resource "aws_instance" "worker" {
  count         = 2
  ami           = "ami-091138d0f0d41ff90"
  instance_type = "t3.micro"
  key_name      = "vinod"

  vpc_security_group_ids = [aws_security_group.k8s_sg.id]

  tags = {
    Name = "k8s-worker-${count.index}"
  }
}