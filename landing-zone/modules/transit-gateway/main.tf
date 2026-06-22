locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "personal-landing-zone"
    },
    var.tags
  )
}

resource "aws_ec2_transit_gateway" "this" {
  description                    = "${var.name} - hub-and-spoke TGW for personal lab landing zone"
  amazon_side_asn                = var.amazon_side_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "disable"
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.common_tags, {
    Name = var.name
  })
}

# Single shared TGW route table - simple hub-and-spoke model for a personal lab.
# (Enterprise builds typically split this into multiple TGW route tables for segmentation.)
resource "aws_ec2_transit_gateway_route_table" "this" {
  transit_gateway_id = aws_ec2_transit_gateway.this.id

  tags = merge(local.common_tags, {
    Name = "${var.name}-rt"
  })
}

# ---------- VPC Attachments (hub + every spoke) ----------
resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  for_each           = var.vpc_attachments
  transit_gateway_id = aws_ec2_transit_gateway.this.id
  vpc_id             = each.value.vpc_id
  subnet_ids         = each.value.subnet_ids

  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false

  tags = merge(local.common_tags, {
    Name = "${var.name}-attach-${each.key}"
  })
}

# ---------- Associate every attachment with the shared route table ----------
resource "aws_ec2_transit_gateway_route_table_association" "this" {
  for_each                       = aws_ec2_transit_gateway_vpc_attachment.this
  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

# ---------- Propagate every attachment's routes into the shared route table ----------
resource "aws_ec2_transit_gateway_route_table_propagation" "this" {
  for_each                       = aws_ec2_transit_gateway_vpc_attachment.this
  transit_gateway_attachment_id  = each.value.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}

# ---------- Spoke VPC route tables: send 0.0.0.0/0 (or hub CIDR) via TGW ----------
# This routes spoke egress traffic to the hub (for centralized firewall/NAT inspection).
# For_each uses static keys (spoke names) so plan is deterministic;
# route_table_id values are resolved at apply time once VPC module outputs are available.
resource "aws_route" "spoke_to_hub" {
  for_each = var.spoke_route_table_ids

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.this,
    aws_ec2_transit_gateway_route_table_propagation.this,
  ]
}

# ---------- Hub VPC route tables: explicit routes back to each spoke CIDR via TGW ----------
resource "aws_route" "hub_to_spokes" {
  for_each = {
    for rt_id in var.hub_route_table_ids :
    rt_id => {
      for spoke_key, cidr in var.spoke_cidrs :
      spoke_key => cidr
    }
  }

  route_table_id         = each.key
  destination_cidr_block = each.value
  transit_gateway_id     = aws_ec2_transit_gateway.this.id

  depends_on = [
    aws_ec2_transit_gateway_vpc_attachment.this,
    aws_ec2_transit_gateway_route_table_propagation.this,
  ]
}
