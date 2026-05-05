############################################
# 🔹 TERRAFORM SETTINGS
############################################
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket  = "vinod-terraform-states"   # ✅ must exist
    key     = "k8s/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true

    # ❌ REMOVE THIS (no DynamoDB)
    # dynamodb_table = "terraform-lock"
  }
}

############################################
# 🔹 PROVIDER
############################################
provider "aws" {
  region = "us-east-1"
}

############################################
# 🔹 FETCH LATEST UBUNTU AMI
############################################
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

############################################
# 🔹 SECURITY GROUP
############################################
resource "aws_security_group" "k8s_sg" {
  name        = "k8s-sg"
  description = "Kubernetes Security Group"

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
    Name = "k8s-sg"
  }
}

############################################
# 🔹 MASTER NODE
############################################
resource "aws_instance" "master" {
  ami           = data.aws_ami.ubuntu.id
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

############################################
# 🔹 WORKER NODE
############################################
resource "aws_instance" "worker" {
  ami           = data.aws_ami.ubuntu.id
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