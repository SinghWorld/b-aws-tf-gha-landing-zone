output "hub_vpc_id" {
  value = module.hub_vpc.vpc_id
}

output "spoke_vpc_ids" {
  value = {
    dev    = module.dev_vpc.vpc_id
    test   = module.test_vpc.vpc_id
    prod   = module.prod_vpc.vpc_id
    shared = module.shared_services_vpc.vpc_id
  }
}

output "transit_gateway_id" {
  value = module.transit_gateway.tgw_id
}

output "environment_role_arns" {
  value = module.iam_boundaries.environment_role_arns
}

output "log_bucket_name" {
  value = module.logging.log_bucket_name
}

output "backup_vault_arn" {
  value = module.backup.backup_vault_arn
}

output "github_actions_role_arn" {
  description = "Put this value into the GitHub repo secret AWS_GITHUB_OIDC_ROLE_ARN"
  value       = module.github_oidc.role_arn
}
