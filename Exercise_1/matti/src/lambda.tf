variable "enable_lambda" {
  description = "Provision Task 3 serverless offload (Lambda + Function URL)"
  type        = bool
  default     = false
}

data "aws_iam_role" "lab" {
  count = var.enable_lambda ? 1 : 0 # only enabled when enable_lambda is set
  name  = "LabRole"                 # As I cannot create my own role, reuse the preexistent LearnerLab Role
}

data "archive_file" "lambda_zip" {
  count       = var.enable_lambda ? 1 : 0
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/lambda.zip"
}

# IMPORTANT: as we provision 0 or 1 resources, we have to index them with [0],
# the count at the top stops the provisioning when lambda is not set, so no out
# of bounds reads
resource "aws_lambda_function" "render" {
  count            = var.enable_lambda ? 1 : 0
  function_name    = "tictactoe-render-bitmap"
  role             = data.aws_iam_role.lab[0].arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  timeout          = 30
  memory_size      = 512
}

resource "aws_lambda_function_url" "render" {
  count              = var.enable_lambda ? 1 : 0
  function_name      = aws_lambda_function.render[0].function_name
  authorization_type = "NONE"
}

output "lambda_url" {
  value = var.enable_lambda ? aws_lambda_function_url.render[0].function_url : null
}
