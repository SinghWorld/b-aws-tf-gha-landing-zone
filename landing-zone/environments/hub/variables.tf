variable "aws_region" {
  description = "AWS region for the lab (kept to one region to control cost/blast radius)"
  type        = string
  default     = "us-east-1"
}

variable "azs" {
  description = "Availability zones to use within the region"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "trusted_principal_arns" {
  description = "Your IAM user ARN(s) allowed to assume the per-environment roles"
  type        = list(string)
}

variable "log_bucket_name" {
  description = "Globally unique S3 bucket name for CloudTrail/Config logs"
  type        = string
}

variable "github_org" {
  description = "Your GitHub username or org (e.g. SinghWorld)"
  type        = string
}

variable "github_repo" {
  description = "Name of this repository, used to scope the GitHub Actions OIDC trust policy"
  type        = string
}
