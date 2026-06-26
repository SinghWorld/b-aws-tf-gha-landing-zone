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
  description                     = "${var.name} - hub-and-spoke TGW for personal lab landing zone"
  amazon_side_asn                 = var.amazon_side_asn
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

# ---------- Default route on the shared TGW route table → hub attachment ----------
# Without this, any traffic sent to the TGW that does not match a more-specific
# propagated CIDR (e.g. a spoke's 0.0.0.0/0 default route heading for the internet)
# has nowhere to go and is dropped. Pinning 0.0.0.0/0 to the hub forces all
# non-VPC-bound traffic to traverse the hub, which is where NAT lives.
# More-specific VPC CIDRs from propagation win over this default for inter-VPC
# traffic, so spoke-to-spoke still works directly.
resource "aws_ec2_transit_gateway_route" "default_to_hub" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.this[var.hub_key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.this.id
}


