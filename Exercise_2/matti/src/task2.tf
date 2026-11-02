variable "task_2" {
  description = "Whether to provision infrastructure for task 1."
  type        = bool
  default     = false
}

# Nodes A and B: only SSH from outside
resource "aws_security_group" "node_2" {
  count = var.task_2 ? 1 : 0
  name  = "task2-node"

  ingress {
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

# Redis: SSH + 6379 only from the nodes' security group
resource "aws_security_group" "redis" {
  count = var.task_2 ? 1 : 0
  name  = "task2-redis"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.node_2[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "redis" {
  count                  = var.task_2 ? 1 : 0
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.redis[0].id]
  key_name               = "vockey"
  availability_zone      = "us-east-1b"

  user_data_replace_on_change = true
  user_data                   = <<-EOF
              #!/bin/bash
              dnf install -y redis6
              sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis6/redis6.conf
              sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis6/redis6.conf
              systemctl enable --now redis6
              EOF

  tags = {
    Name = "task2-redis"
  }
}

resource "aws_instance" "nodes_2" {
  count                  = var.task_2 ? local.node_count_2 : 0
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.node_2[0].id]
  key_name               = "vockey"
  availability_zone      = "us-east-1b"

  user_data_replace_on_change = true
  user_data                   = <<-EOF
              #!/bin/bash
              dnf install -y python3-pip
              sudo -u ec2-user pip3 install --user redis
              EOF

  tags = {
    Name = "task2-node-${local.node_ids[count.index]}"
  }
}

output "task_2" {
  description = "IPs of the replicated counter nodes"
  value = var.task_2 ? {
    redis_private = aws_instance.redis[0].private_ip
    nodes         = { for i, vm in aws_instance.nodes_2 : local.node_ids[i] => vm.public_ip }
  } : null
}
