variable "account_id" {
  description = "AWS account ID (used in bucket policies)"
  type        = string
}

variable "log_bucket_name" {
  description = "Globally unique S3 bucket name for centralized logs (CloudTrail + Config)"
  type        = string
}

variable "trail_name" {
  description = "Name for the CloudTrail trail"
  type        = string
  default     = "personal-lab-trail"
}

variable "log_retention_days" {
  description = "Number of days to retain logs in the bucket before transition/expiry"
  type        = number
  default     = 365
}

variable "tags" {
  description = "Tags to apply to logging resources"
  type        = map(string)
  default     = {}
}
