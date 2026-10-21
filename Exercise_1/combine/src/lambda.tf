variable "enable_lambda" {
  description = "Provision Task 3 serverless offload (Lambda + Function URL)"
  type        = bool
  default     = false
}

# Reference AWS Learner Lab's pre-created IAM Role
data "aws_iam_role" "lab_role" {
  count = var.enable_lambda ? 1 : 0 # only enabled when enable_lambda is set

  name = "LabRole"
}

# Automatically install Linux-compatible Pillow (PIL) into a build folder
resource "terraform_data" "install_dependencies" {
  count = var.enable_lambda ? 1 : 0 # only enabled when enable_lambda is set

  triggers_replace = [
    md5("${path.module}/tic-tac-toe/tic-tac-toe/lambda/lambda_function.py")
  ]


  provisioner "local-exec" {
    command = <<EOT
      rm -rf ${path.module}/lambda_build
      mkdir -p ${path.module}/lambda_build
      cp ${path.module}/lambda/lambda_function.py ${path.module}/lambda_build/
      pip install --platform manylinux2014_x86_64 --target ${path.module}/lambda_build --implementation cp --python-version 3.11 --only-binary=:all: --upgrade pillow
    EOT
  }
}

# Zip the handler code + installed dependencies
data "archive_file" "lambda_zip" {
  count = var.enable_lambda ? 1 : 0 # only enabled when enable_lambda is set

  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda_build.zip"

  depends_on = [terraform_data.install_dependencies[0]]
}

# Deploy the AWS Lambda Function
resource "aws_lambda_function" "render_lambda" {
  count = var.enable_lambda ? 1 : 0 # only enabled when enable_lambda is set

  function_name    = "tic-tac-toe-render-lambda"
  role             = data.aws_iam_role.lab_role[0].arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256
  timeout          = 10
  memory_size      = 512

  depends_on = [data.archive_file.lambda_zip[0]]
}

# Create a public Function URL for HTTP invocations
resource "aws_lambda_function_url" "lambda_url" {
  count = var.enable_lambda ? 1 : 0 # only enabled when enable_lambda is set

  function_name      = aws_lambda_function.render_lambda[0].function_name
  authorization_type = "NONE"
}

# Output the generated Function URL
output "lambda_function_url" {
  description = "Public Function URL for the Lambda function"
  value = var.enable_lambda ? aws_lambda_function_url.lambda_url[0].function_url : null
}
