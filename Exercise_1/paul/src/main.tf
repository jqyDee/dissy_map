terraform {
  required_version = ">= 1.0.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
    region = "us-east-1"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_security_group" "ssh_sg" {
  name        = "exc01-ssh-sg"
  description = "Allow inbound SSH access"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "port_forward" {
  name        = "baseline_application_access"
  description = "Allow inbound application access"

  ingress {
    description = "Frontend"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Backend"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "my_vm" {
    ami = data.aws_ami.amazon_linux_2023.id
    instance_type = "t2.micro"
    key_name = "vockey"
    vpc_security_group_ids = [aws_security_group.ssh_sg.id, aws_security_group.port_forward.id]

    user_data_replace_on_change = true

    user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker python3 python3-pip time unzip
              systemctl enable --now docker
              usermod -aG docker ec2-user

              # Automatically download and install Compose & Buildx plugins
              mkdir -p /usr/libexec/docker/cli-plugins
              curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 -o /usr/libexec/docker/cli-plugins/docker-compose
              curl -SL https://github.com/docker/buildx/releases/download/v0.17.0/buildx-v0.17.0.linux-amd64 -o /usr/libexec/docker/cli-plugins/docker-buildx
              chmod +x /usr/libexec/docker/cli-plugins/docker-compose
              chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
              EOF


    associate_public_ip_address = true

    tags = {
        Name = "Task1-Baseline-VM"
    }
}

output "instance_public_ip" {
    description = "public ip address of the EC2 instance"
    value = aws_instance.my_vm.public_ip
}