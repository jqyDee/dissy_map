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

resource "aws_security_group" "ex5_auction" {
  name = "ex5-auction"

  ingress { #one block per inbound rule
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.my_ip}/32"] #who may connect (IP range)
  }


  ingress {
    description = "zookeeper"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


# ---- ZooKeeper server (runs in docker)

resource "aws_instance" "zk" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ex5_auction.id]
  key_name               = "vockey"

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash
              dnf install -y docker
              systemctl enable --now docker
              docker run -d --name zk --restart unless-stopped -p 2181:2181 zookeeper
              EOF
  tags = {
    Name = "ex5-zookeper"
  }
}

resource "aws_instance" "node" {
  count                  = 5
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.ex5_auction.id]
  key_name               = "vockey"

  user_data_replace_on_change = true

  user_data = <<-EOF
              #!/bin/bash 
              dnf install -y python3 python3-pip # install python
              python3 -m pip install kazoo # install kazoo
              echo "${filebase64("../auction.py")}" | base64 -d > /home/ec2-user/auction.py   # terraform reads local auction.py, encodes it as one long text line VM decodes it back to hope folder
              chown ec2-user /home/ec2-user/auction.py      # file belonds to user 
              EOF
  tags = {
    Name = "ex5-node-${count.index}"
  }

}


output "zk_private_ip" {
  description = "private ip of ZooKeeper, nodes connect to this"
  value       = aws_instance.zk.private_ip
}

output "node_public_ips" {
  description = "public ips of the 5 nodes for ssh"
  value       = aws_instance.node[*].public_ip
}
