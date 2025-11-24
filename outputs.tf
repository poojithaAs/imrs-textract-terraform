output "input_bucket" {
  value = aws_s3_bucket.imrs_bucket.bucket
}

output "output_bucket" {
  value = aws_s3_bucket.output_bucket.bucket
}

output "lambda_name" {
  value = aws_lambda_function.imrs_lambda.function_name
}
