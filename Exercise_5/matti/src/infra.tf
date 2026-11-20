resource "aws_security_group" "znodes" {
  name = "nodes-sec-group"

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

resource "aws_security_group" "zookeeper" {
  name = "zookeeper-sec-group"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 2181
    to_port         = 2181
    protocol        = "tcp"
    security_groups = [aws_security_group.znodes.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "zookeeper" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.zookeeper.id]
  key_name               = "vockey"
  availability_zone      = "us-east-1b"

  user_data_replace_on_change = true
  user_data                   = <<-EOF
              #!/bin/bash
              dnf install -y docker
              systemctl enable --now docker

              docker run -d --name zk --restart unless-stopped -p 2181:2181 \
                -v /var/lib/zk-data:/data -v /var/lib/zk-datalog:/datalog \
                zookeeper:3.9
              EOF

  tags = {
    Name = "zookeeper"
  }
}

resource "aws_instance" "znodes" {
  count                  = local.node_count
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.small"
  vpc_security_group_ids = [aws_security_group.znodes.id]
  key_name               = "vockey"
  availability_zone      = "us-east-1b"

  user_data_replace_on_change = true
  user_data                   = <<-EOF
              #!/bin/bash
              dnf install -y python3-pip

              # task3
              dnf install -y iptables-nft

              sudo -u ec2-user -H pip3 install --user kazoo
              echo "ZK_HOSTS=${aws_instance.zookeeper.private_ip}:2181" >> /etc/environment
              EOF

  tags = {
    Name = "znode-${local.node_ids[count.index]}"
  }
}

output "infra" {
  description = "Ips"
  value = {
    zk_private = aws_instance.zookeeper.private_ip
    nodes      = { for i, vm in aws_instance.znodes : local.node_ids[i] => vm.public_ip }
  }
}
