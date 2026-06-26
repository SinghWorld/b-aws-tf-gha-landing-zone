variable "github_org" {
  description = "Your GitHub username or org (e.g. SinghWorld)"
  type        = string
}

variable "github_repo" {
  description = "Repository name that's allowed to assume this role (e.g. b-aws-tf-gha-landing-zone)"
  type        = string
}

variable "allowed_branches" {
  description = "Branches allowed to assume this role for apply (push events). PRs from any branch can still plan via pull_request trigger."
  type        = list(string)
  default     = ["main"]
}

variable "allowed_environments" {
  description = "GitHub Environments whose jobs may assume this role. When a workflow job uses `environment: <name>`, the OIDC sub claim becomes `repo:ORG/REPO:environment:<name>` instead of the branch or PR form. The `production` environment is gated for manual approval, so it must be in this list or the apply job cannot assume the role."
  type        = list(string)
  default     = ["production"]
}

variable "tags" {
  description = "Tags to apply"
  type        = map(string)
  default     = {}
}
