variable "environments" {
  description = "List of environment names to create boundary policies + roles for (e.g. dev, test, prod)"
  type        = list(string)
  default     = ["dev", "test", "prod"]
}

variable "trusted_principal_arns" {
  description = "ARNs (IAM users/roles) allowed to assume the environment roles. For a personal lab this is typically your own IAM user ARN."
  type        = list(string)
}

variable "tags" {
  description = "Tags to apply to IAM resources"
  type        = map(string)
  default     = {}
}
