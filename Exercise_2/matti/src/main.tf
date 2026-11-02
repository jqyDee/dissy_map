locals {
  node_ids     = ["A", "B"]
  node_count_1 = 2
  app_path_1   = "app-task-1"
  node_count_2 = 2
  app_path_2   = "app-task-2"

  deploy_targets = merge(
    { for i, vm in aws_instance.nodes_1 : "task1-${local.node_ids[i]}" => {
      id = vm.id, host = vm.public_ip, app = local.app_path_1
    } },
    { for i, vm in aws_instance.nodes_2 : "task2-${local.node_ids[i]}" => {
      id = vm.id, host = vm.public_ip, app = local.app_path_2
    } },
  )
}

resource "terraform_data" "deploy_nodes" {
  for_each = local.deploy_targets

  triggers_replace = [
    each.value.id,
    sha1(join("", [for f in fileset("${path.module}/${each.value.app}", "**") : filesha1("${path.module}/${each.value.app}/${f}")]))
  ]

  connection {
    type        = "ssh"
    host        = each.value.host
    user        = "ec2-user"
    private_key = file(pathexpand("~/.ssh/labsuser.pem"))
  }

  # Wait until user_data (dnf installs) is done
  provisioner "remote-exec" {
    inline = ["cloud-init status --wait > /dev/null"]
  }

  # Uploads local ./app-{task-name} to /home/ec2-user/app
  provisioner "file" {
    source      = "${path.module}/${each.value.app}"
    destination = "/home/ec2-user"
  }
}
