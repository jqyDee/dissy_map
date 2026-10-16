provider "aws" {
  region = "us-east-1"
}

# Fetch the latest Amazon Linux 2023 AMI dynamically
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Security group allowing SSH access
resource "aws_security_group" "ssh_access" {
  name        = "baseline_ssh_access"
  description = "Allow inbound SSH access"

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 Instance
resource "aws_instance" "baseline_vm" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t2.micro"
  key_name               = "vockey" # Default key provided by AWS Learner Lab
  vpc_security_group_ids = [aws_security_group.ssh_access.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y docker python3 python3-pip
              systemctl enable --now docker
              usermod -aG docker ec2-user
              
              # Automatically download and install Compose & Buildx plugins
              mkdir -p /usr/libexec/docker/cli-plugins
              curl -SL https://github.com/docker/compose/releases/download/v2.29.2/docker-compose-linux-x86_64 -o /usr/libexec/docker/cli-plugins/docker-compose
              curl -SL https://github.com/docker/buildx/releases/download/v0.17.0/buildx-v0.17.0.linux-amd64 -o /usr/libexec/docker/cli-plugins/docker-buildx
              chmod +x /usr/libexec/docker/cli-plugins/docker-compose
              chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
              EOF

  tags = {
    Name = "Baseline-Execution-VM"
  }
}

# Output the public IP so you can connect to it
output "public_ip" {
  description = "The public IP of the EC2 instance"
  value       = aws_instance.baseline_vm.public_ip
}
