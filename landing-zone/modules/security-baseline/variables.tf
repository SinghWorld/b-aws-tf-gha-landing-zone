variable "config_recorder_name" {
  description = "Name of the Config recorder (must exist before conformance pack is deployed)"
  type        = string
}

variable "delivery_s3_bucket" {
  description = "S3 bucket name where Config delivers conformance pack compliance reports (reuse your log archive bucket)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to security resources"
  type        = map(string)
  default     = {}
}
