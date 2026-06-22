output "vpc_id" {
  description = "ID of the created VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets (empty list if none created)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = aws_subnet.private[*].id
}

output "private_route_table_ids" {
  description = "IDs of private route tables (used for TGW route propagation)"
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table, if it exists"
  value       = local.has_public_subnets ? aws_route_table.public[0].id : null
}
