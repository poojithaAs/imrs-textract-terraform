terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.3.0"
}

provider "aws" {
  region = "us-east-1"
}

# ----------------------
# S3 BUCKETS
# ----------------------
resource "aws_s3_bucket" "imrs_bucket" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "block" {
  bucket = aws_s3_bucket.imrs_bucket.id
  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls  = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket" "output_bucket" {
  bucket = "${var.bucket_name}-output"
}

# ----------------------
# IAM ROLE FOR LAMBDA
# ----------------------
resource "aws_iam_role" "lambda_role" {
  name = "imrs_textract_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "imrs_textract_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:*"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "textract:*"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "logs:*"
        ]
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

# ----------------------
# ZIP LAMBDA PACKAGE
# ----------------------
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda.zip"
}

# ----------------------
# Lambda Function
# ----------------------
resource "aws_lambda_function" "imrs_lambda" {
  function_name = "imrs_textract_parser"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  timeout       = 300

  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output_bucket.bucket
    }
  }
}

# ----------------------
# S3 → Lambda Trigger
# ----------------------
resource "aws_s3_bucket_notification" "s3_trigger" {
  bucket = aws_s3_bucket.imrs_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.imrs_lambda.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".pdf"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

resource "aws_lambda_permission" "allow_s3" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.imrs_lambda.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.imrs_bucket.arn
}
