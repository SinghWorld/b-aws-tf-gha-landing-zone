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
  description = "Key (within vpc_attachments) identifying the hub VPC, used to build the default route in spokes"
  type        = string
  default     = "hub"
}

variable "spoke_route_table_ids" {
  description = "Map of spoke environment key => list of private route table IDs that need a default route pointed at the TGW (for hub-and-spoke egress via firewall/NAT in the hub)"
  type        = map(list(string))
  default     = {}
}

variable "spoke_cidrs" {
  description = "Map of spoke environment key => VPC CIDR, used to add routes from the hub VPC route table back to each spoke"
  type        = map(string)
  default     = {}
}

variable "hub_route_table_ids" {
  description = "List of hub VPC private route table IDs that need routes to each spoke CIDR via the TGW"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to TGW resources"
  type        = map(string)
  default     = {}
}
