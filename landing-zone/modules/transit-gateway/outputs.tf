output "tgw_id" {
  description = "ID of the Transit Gateway"
  value       = aws_ec2_transit_gateway.this.id
}

output "tgw_route_table_id" {
  description = "ID of the shared TGW route table"
  value       = aws_ec2_transit_gateway_route_table.this.id
}

output "attachment_ids" {
  description = "Map of attachment key => TGW VPC attachment ID"
  value       = { for k, v in aws_ec2_transit_gateway_vpc_attachment.this : k => v.id }
}
