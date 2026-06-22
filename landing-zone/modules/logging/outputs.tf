output "log_bucket_name" {
  description = "Name of the centralized log archive S3 bucket"
  value       = aws_s3_bucket.log_archive.id
}

output "cloudtrail_arn" {
  description = "ARN of the CloudTrail trail"
  value       = aws_cloudtrail.this.arn
}

output "config_recorder_name" {
  description = "Name of the AWS Config configuration recorder"
  value       = aws_config_configuration_recorder.this.name
}
