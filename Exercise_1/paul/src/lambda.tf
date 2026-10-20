# 1. Reference AWS Learner Lab's pre-created IAM Role
data "aws_iam_role" "lab_role" {
  name = "LabRole"
}

# 2. Automatically install Linux-compatible Pillow (PIL) into a build folder
resource "null_resource" "install_dependencies" {
  triggers = {
    code_hash = filemd5("${path.module}/tic-tac-toe/tic-tac-toe/lambda/lambda_function.py")
  }

  provisioner "local-exec" {
    command = <<EOT
      rm -rf ${path.module}/lambda_build
      mkdir -p ${path.module}/lambda_build
      cp ${path.module}/lambda/lambda_function.py ${path.module}/lambda_build/
      pip install --platform manylinux2014_x86_64 --target ${path.module}/lambda_build --implementation cp --python-version 3.11 --only-binary=:all: --upgrade pillow
    EOT
  }
}

# 3. Zip the handler code + installed dependencies
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda_build"
  output_path = "${path.module}/lambda_package.zip"

  depends_on = [null_resource.install_dependencies]
}

# 4. Deploy the AWS Lambda Function
resource "aws_lambda_function" "render_lambda" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "tic-tac-toe-render-lambda"
  role             = data.aws_iam_role.lab_role.arn
  handler          = "lambda_function.handler"
  runtime          = "python3.11"
  timeout          = 10
  memory_size      = 512
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  depends_on = [data.archive_file.lambda_zip]
}

# 5. Create a public Function URL for HTTP invocations
resource "aws_lambda_function_url" "lambda_url" {
  function_name      = aws_lambda_function.render_lambda.function_name
  authorization_type = "NONE"
}

# 6. Grant unauthenticated public access to the Function URL
resource "aws_lambda_permission" "allow_public_url" {
  statement_id           = "AllowFunctionURLPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.render_lambda.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# 7. Output the generated Function URL
output "lambda_function_url" {
  description = "Public Function URL for the Lambda function"
  value       = aws_lambda_function_url.lambda_url.function_url
}