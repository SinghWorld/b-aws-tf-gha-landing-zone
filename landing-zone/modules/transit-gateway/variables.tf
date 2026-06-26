variable "name" {
  description = "Name for the Transit Gateway"
  type        = string
  default     = "personal-lab-tgw"
}

variable "amazon_side_asn" {
  description = "ASN for the Amazon side of the Transit Gateway"
  type        = number
  default     = 64512
}

# Map of attachment_key => { vpc_id, subnet_ids } for every VPC to attach (hub + each spoke)
variable "vpc_attachments" {
  description = "Map of VPCs to attach to the TGW. Key is a friendly name (e.g. hub, dev, test, prod, shared)."
  type = map(object({
    vpc_id     = string
    subnet_ids = list(string)
  }))
}

variable "hub_key" {
  description = "Key (within vpc_attachments) identifying the hub VPC"
  type        = string
  default     = "hub"
}

variable "tags" {
  description = "Tags to apply to TGW resources"
  type        = map(string)
  default     = {}
}
