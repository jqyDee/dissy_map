terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}


variable "my_ip" {
  description = "public ip of my laptop, the only address allowed to connect"
  type        = string
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "secondtask" {
  name = "ex2-shared-state"

  ingress { #one block per inbound rule
    description = "SHH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"] #who may connect (IP range)
  }

  ingress {
    description = "task 1: node B(UDP)"
    from_port   = 5002
    to_port     = 5002
    protocol    = "udp"
    cidr_blocks = ["${var.my_ip}/32"] #who may connect (IP range)
  }

  ingress {
    description = "task 2: redis"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ---- the VM: node B + Redis 


resource "aws_instance" "vm" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.secondtask.id]
  key_name               = "vockey"

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker python3 python3-pip
              systemctl enable --now docker
              usermod -aG docker ec2-user
              docker run -d --name redis --restart unless-stopped -p 6379:6379 redis
              python3 -m pip install redis
              EOF
  tags = {
    Name = "ex2-node-b-redis"
  }

}


output "public_ip" {
  description = "public ip of the VM"
  value       = aws_instance.vm.public_ip
}
