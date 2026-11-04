variable "ssh_key_path" {
  description = "Local path to vockey private key (.pem)"
  default     = "~/.ssh/labsuser.pem"
}

variable "counter_script" {
  description = "Task 1 script to run: counter_1_1.py or counter_1_4.py"
  default     = "counter_1_1.py"
}

variable "enable_task2" {
  description = "Set to true to provision Redis node and deploy task 2 scripts"
  type        = bool
  default     = false
}
