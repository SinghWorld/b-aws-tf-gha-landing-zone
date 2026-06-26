locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "personal-landing-zone"
    },
    var.tags
  )

  # Trust condition subjects: one for each allowed branch (push/apply) plus
  # a wildcard for pull_request events (which use a different sub format),
  # plus one per allowed GitHub Environment. When a workflow job targets an
  # environment (e.g. `environment: production` for an approval gate), the
  # OIDC sub becomes `repo:ORG/REPO:environment:<name>` regardless of the
  # underlying event - so omitting these denies the apply job entirely.
  branch_subs      = [for b in var.allowed_branches : "repo:${var.github_org}/${var.github_repo}:ref:refs/heads/${b}"]
  pr_sub           = "repo:${var.github_org}/${var.github_repo}:pull_request"
  environment_subs = [for e in var.allowed_environments : "repo:${var.github_org}/${var.github_repo}:environment:${e}"]
}

# GitHub's OIDC provider - reuse the existing one if you already created it
# for another repo, otherwise this creates it. AWS allows only one per
# unique issuer URL per account, so if apply fails with "already exists",
# import the existing provider instead:
#   terraform import module.github_oidc.aws_iam_openid_connect_provider.github \
#     arn:aws:iam::<account_id>:oidc-provider/token.actions.githubusercontent.com
#
# Note: AWS added GitHub's CA to its trusted root list, so the thumbprint
# below is no longer load-bearing for validation - AWS validates GitHub's
# certificate chain directly. It's kept here because the Terraform AWS
# provider still requires a value in some versions; if your provider version
# makes thumbprint_list optional, you can omit it entirely.
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = local.common_tags
}

data "aws_iam_policy_document" "trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = concat(local.branch_subs, [local.pr_sub], local.environment_subs)
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-landing-zone-role"
  assume_role_policy = data.aws_iam_policy_document.trust.json

  tags = local.common_tags
}

# Scoped to what the landing zone actually needs to manage, rather than
# blanket AdministratorAccess. Extend this list if terraform plan/apply
# errors on a missing permission for a resource type you add later.
resource "aws_iam_role_policy_attachment" "power_user" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# PowerUserAccess excludes IAM management, but this repo's IAM module needs
# to create/manage roles and policies - so grant a scoped IAM policy on top.
data "aws_iam_policy_document" "iam_management" {
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:UpdateRole",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:GetPolicy",
      "iam:GetPolicyVersion",
      "iam:ListPolicyVersions",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      # Required as a precondition check before AWS will let us delete a
      # role (even when no instance profiles are attached). Without this,
      # `terraform destroy` fails with AccessDenied on every role. Added
      # when destroy of env-admin / backup / config-recorder roles broke.
      "iam:ListInstanceProfilesForRole",
      "iam:TagRole",
      "iam:TagPolicy",
      "iam:PassRole",
      "iam:PutRolePermissionsBoundary",
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:TagOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "iam_management" {
  name   = "iam-management"
  role   = aws_iam_role.github_actions.name
  policy = data.aws_iam_policy_document.iam_management.json
}
