resource "aws_instance" "node_a" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  key_name                    = "vockey"
  vpc_security_group_ids      = [aws_security_group.counter_sg.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y python3
  EOF

  tags = { Name = "exc02-node-a" }
}

resource "aws_instance" "node_b" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = "t2.micro"
  key_name                    = "vockey"
  vpc_security_group_ids      = [aws_security_group.counter_sg.id]
  associate_public_ip_address = true

  user_data_replace_on_change = true
  user_data = <<-EOF
    #!/bin/bash
    dnf install -y python3
  EOF

  tags = { Name = "exc02-node-b" }
}

resource "null_resource" "deploy_node_a" {
  depends_on = [aws_instance.node_a, aws_instance.node_b]

  triggers = {
    script        = var.counter_script
    node_b_ip     = aws_instance.node_b.private_ip
    counter_1_1   = filemd5("${path.module}/counter_1_1.py")
    counter_1_4   = filemd5("${path.module}/counter_1_4.py")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.node_a.public_ip
    user        = "ec2-user"
    private_key = file(var.ssh_key_path)
    timeout     = "4m"
  }

  provisioner "remote-exec" {
    inline = ["sudo cloud-init status --wait"]
  }

  provisioner "file" {
    source      = "${path.module}/counter_1_1.py"
    destination = "/home/ec2-user/counter_1_1.py"
  }

  provisioner "file" {
    source      = "${path.module}/counter_1_4.py"
    destination = "/home/ec2-user/counter_1_4.py"
  }

  provisioner "remote-exec" {
    inline = [
      "pkill -f 'counter_1' || true",
      "nohup python3 /home/ec2-user/${var.counter_script} --id A --port 5001 --peer-ip ${aws_instance.node_b.private_ip} --peer-port 5002 > /home/ec2-user/counter.log 2>&1 &",
      "sleep 1",
    ]
  }
}

resource "null_resource" "deploy_node_b" {
  depends_on = [aws_instance.node_a, aws_instance.node_b]

  triggers = {
    script      = var.counter_script
    node_a_ip   = aws_instance.node_a.private_ip
    counter_1_1 = filemd5("${path.module}/counter_1_1.py")
    counter_1_4 = filemd5("${path.module}/counter_1_4.py")
  }

  connection {
    type        = "ssh"
    host        = aws_instance.node_b.public_ip
    user        = "ec2-user"
    private_key = file(var.ssh_key_path)
    timeout     = "4m"
  }

  provisioner "remote-exec" {
    inline = ["sudo cloud-init status --wait"]
  }

  provisioner "file" {
    source      = "${path.module}/counter_1_1.py"
    destination = "/home/ec2-user/counter_1_1.py"
  }

  provisioner "file" {
    source      = "${path.module}/counter_1_4.py"
    destination = "/home/ec2-user/counter_1_4.py"
  }

  provisioner "remote-exec" {
    inline = [
      "pkill -f 'counter_1' || true",
      "nohup python3 /home/ec2-user/${var.counter_script} --id B --port 5002 --peer-ip ${aws_instance.node_a.private_ip} --peer-port 5001 > /home/ec2-user/counter.log 2>&1 &",
      "sleep 1",
    ]
  }
}
