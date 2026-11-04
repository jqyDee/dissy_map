variable "task_1" {
  description = "Whether to provision infrastructure for task 1."
  type        = bool
  default     = false
}

variable "machine_counter_1" {
  description = "The count of machines provisioned."
  type        = number
  default     = 2
}

resource "aws_security_group" "sec_node_1" {
  count = var.task_1 ? 1 : 0
  name  = "task1-replicated-counter"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nodes_1" {
  count                  = var.task_1 ? local.node_count_1 : 0
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.sec_node_1[0].id]
  key_name               = "vockey"
  availability_zone      = "us-east-1b"

  user_data_replace_on_change = true
  user_data                   = <<-EOF
              #!/bin/bash
              dnf update -y
              dnf install -y python3 python3-pip
              EOF

  tags = {
    Name = "task1-node-${local.node_ids[count.index]}"
  }
}


output "task_1" {
  description = "Public IPs of the replicated counter nodes"
  value = var.task_1 ? {
    for i, vm in aws_instance.nodes_1 : local.node_ids[i] => { public = vm.public_ip, private = vm.private_ip }
  } : null
}
