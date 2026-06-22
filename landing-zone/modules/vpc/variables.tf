variable "name" {
  description = "Name prefix for the VPC and its resources (e.g. hub, dev, test, prod, shared)"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for this VPC"
  type        = string
}

variable "azs" {
  description = "Availability zones to spread subnets across"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Leave empty list if no public subnets needed."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to provision a NAT Gateway for private subnet egress. Disable for spokes that route egress via the hub/firewall instead."
  type        = bool
  default     = false
}

variable "single_nat_gateway" {
  description = "Use a single shared NAT Gateway instead of one per AZ (cheaper for lab use)"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment tag value: dev, test, prod, shared, hub"
  type        = string
}

variable "tags" {
  description = "Additional tags to merge into all resources"
  type        = map(string)
  default     = {}
}

variable "flow_log_destination_arn" {
  description = "ARN of the CloudWatch Log Group or S3 bucket to send VPC Flow Logs to. Set null to disable flow logs for this VPC."
  type        = string
  default     = null
}

variable "flow_log_destination_type" {
  description = "Destination type for flow logs: cloud-watch-logs or s3"
  type        = string
  default     = "cloud-watch-logs"
}
