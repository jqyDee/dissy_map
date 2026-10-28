output "node_a_public_ip" {
  value = aws_instance.node_a.public_ip
}

output "node_a_private_ip" {
  value = aws_instance.node_a.private_ip
}

output "node_b_public_ip" {
  value = aws_instance.node_b.public_ip
}

output "node_b_private_ip" {
  value = aws_instance.node_b.private_ip
}

output "redis_public_ip" {
  value = var.enable_task2 ? aws_instance.redis_node[0].public_ip : "task2 disabled"
}

output "ssh_node_a" {
  description = "SSH command for node A"
  value       = "ssh -i ${var.ssh_key_path} ec2-user@${aws_instance.node_a.public_ip}"
}

output "ssh_node_b" {
  description = "SSH command for node B"
  value       = "ssh -i ${var.ssh_key_path} ec2-user@${aws_instance.node_b.public_ip}"
}

output "ssh_redis" {
  description = "SSH command for Redis node"
  value       = var.enable_task2 ? "ssh -i ${var.ssh_key_path} ec2-user@${aws_instance.redis_node[0].public_ip}" : "task2 disabled"
}

output "watch_task1_logs" {
  value = "tail -f /home/ec2-user/counter.log"
}

output "watch_task2_logs" {
  value = "tail -f /home/ec2-user/counter2.log"
}

output "benchmark" {
  description = "Run benchmark with correct IPs"
  value       = "./benchmark.sh ${aws_instance.node_a.public_ip} ${aws_instance.node_a.private_ip} ${aws_instance.node_b.public_ip} ${aws_instance.node_b.private_ip} ${var.enable_task2 ? aws_instance.redis_node[0].private_ip : "REDIS_DISABLED"}"
}

output "run_task2_node_a" {
  description = "Paste this into node A's SSH session to start task 2"
  value       = var.enable_task2 ? "python3 -u ~/counter_2.py --id A --redis-ip ${aws_instance.redis_node[0].private_ip}" : "task2 disabled"
}

output "run_task2_node_b" {
  description = "Paste this into node B's SSH session to start task 2"
  value       = var.enable_task2 ? "python3 -u ~/counter_2.py --id B --redis-ip ${aws_instance.redis_node[0].private_ip}" : "task2 disabled"
}
