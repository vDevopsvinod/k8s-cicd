provider "aws" {
  region = "us-east-1"
}

# 🔹 Use existing Security Group (READ ONLY)
data "aws_security_group" "k8s_sg" {
  name = "k8s-sg"
}

# 🔹 Master Node
resource "aws_instance" "master" {
  ami           = "ami-091138d0f0d41ff90" # Ubuntu 22.04 (us-east-1)
  instance_type = "t3.micro"
  key_name      = "vinod"

  vpc_security_group_ids = [data.aws_security_group.k8s_sg.id]

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

  vpc_security_group_ids = [data.aws_security_group.k8s_sg.id]

  tags = {
    Name = "k8s-worker-${count.index}"
  }
}