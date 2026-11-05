# Redis instance — single-copy data store for task 2
resource "aws_instance" "redis_node" {
  count                       = var.enable_task2 ? 1 : 0
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  key_name                    = "vockey"
  vpc_security_group_ids      = [aws_security_group.redis_sg.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y redis6
    sed -i 's/^bind .*/bind 0.0.0.0/' /etc/redis6/redis6.conf
    sed -i 's/^protected-mode yes/protected-mode no/' /etc/redis6/redis6.conf
    systemctl enable --now redis6
  EOF

  tags = { Name = "exc02-redis" }
}

# Wait for Redis to be up before deploying counter scripts to the nodes
resource "null_resource" "wait_for_redis" {
  count      = var.enable_task2 ? 1 : 0
  depends_on = [aws_instance.redis_node]

  triggers = {
    redis_instance = aws_instance.redis_node[0].id
  }

  connection {
    type        = "ssh"
    host        = aws_instance.redis_node[0].public_ip
    user        = "ec2-user"
    private_key = file(var.ssh_key_path)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo cloud-init status --wait",
      "until python3 -c \"import socket; s=socket.socket(); s.settimeout(2); s.connect(('localhost', 6379)); s.close()\" 2>/dev/null; do sleep 2; done",
    ]
  }
}

# Deploy counter_2.py and install redis-py on node A
resource "null_resource" "deploy_task2_node_a" {
  count      = var.enable_task2 ? 1 : 0
  depends_on = [aws_instance.node_a, null_resource.wait_for_redis]

  triggers = {
    redis_ip   = aws_instance.redis_node[0].private_ip
    counter_2  = filemd5("${path.module}/counter_2.py")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.node_a.public_ip
    user        = "ec2-user"
    private_key = file(var.ssh_key_path)
    timeout     = "4m"
  }

  provisioner "file" {
    source      = "${path.module}/counter_2.py"
    destination = "/home/ec2-user/counter_2.py"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo dnf install -y python3-pip -q",
      "pip3 install --user redis -q",
    ]
  }
}

# Deploy counter_2.py and install redis-py on node B
resource "null_resource" "deploy_task2_node_b" {
  count      = var.enable_task2 ? 1 : 0
  depends_on = [aws_instance.node_b, null_resource.wait_for_redis]

  triggers = {
    redis_ip   = aws_instance.redis_node[0].private_ip
    counter_2  = filemd5("${path.module}/counter_2.py")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.node_b.public_ip
    user        = "ec2-user"
    private_key = file(var.ssh_key_path)
    timeout     = "4m"
  }

  provisioner "file" {
    source      = "${path.module}/counter_2.py"
    destination = "/home/ec2-user/counter_2.py"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo dnf install -y python3-pip -q",
      "pip3 install --user redis -q",
    ]
  }
}
