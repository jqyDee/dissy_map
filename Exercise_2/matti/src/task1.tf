variable "task_1" {
  description = "Whether to provision infrastructure for task 1."
  type        = bool
  default     = false
}

variable "machine_counter" {
  description = "The count of machines provisioned."
  type        = number
  default     = 2
}

locals {
  node_ids = ["A", "B"]
  app_path = "app-task-1"
}

resource "aws_security_group" "node" {
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

resource "aws_instance" "vm" {
  count                  = var.task_1 ? var.machine_counter : 0
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.node[0].id]
  key_name               = "vockey"

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

resource "terraform_data" "deploy" {
  count = length(aws_instance.vm)

  triggers_replace = [
    aws_instance.vm[count.index].id,
    sha1(join("", [for f in fileset("${path.module}/${local.app_path}", "**") : filesha1("${path.module}/${local.app_path}/${f}")]))
  ]

  connection {
    type        = "ssh"
    host        = aws_instance.vm[count.index].public_ip
    user        = "ec2-user"
    private_key = file(pathexpand("~/.ssh/labsuser.pem"))
  }

  # Wait until user_data (dnf installs) is done
  provisioner "remote-exec" {
    inline = ["cloud-init status --wait > /dev/null"]
  }

  # Uploads local ./app to /home/ec2-user/app
  provisioner "file" {
    source      = "${path.module}/${local.app_path}"
    destination = "/home/ec2-user"
  }
}

output "public_ip" {
  description = "Public IPs of the replicated counter nodes"
  value       = { for i, vm in aws_instance.vm : "task-1-node${local.node_ids[i]}" => vm.public_ip }
}
