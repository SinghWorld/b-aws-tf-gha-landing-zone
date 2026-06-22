output "boundary_policy_arns" {
  description = "Map of environment => permission boundary policy ARN"
  value       = { for k, v in aws_iam_policy.boundary : k => v.arn }
}

output "environment_role_arns" {
  description = "Map of environment => assumable role ARN"
  value       = { for k, v in aws_iam_role.environment_role : k => v.arn }
}
