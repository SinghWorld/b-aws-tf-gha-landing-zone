output "role_arn" {
  description = "ARN of the IAM role GitHub Actions assumes - put this in your repo secret AWS_GITHUB_OIDC_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}
