locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "personal-landing-zone"
    },
    var.tags
  )
}

# ---------- Permission boundary per environment ----------
# Mirrors what an SCP would do at the OU level in a multi-account setup:
# - Deny actions on resources NOT tagged for this environment
# - Deny a fixed list of "dangerous" actions outright (region lock, root protection equivalents)
data "aws_iam_policy_document" "boundary" {
  for_each = toset(var.environments)

  # Allow everything by default within the boundary (the boundary narrows, it doesn't grant)
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Deny acting on resources tagged for a DIFFERENT environment
  statement {
    sid    = "DenyCrossEnvironmentAccess"
    effect = "Deny"
    actions = [
      "ec2:*",
      "rds:*",
      "s3:*",
      "dynamodb:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:ResourceTag/Environment"
      values   = [each.key]
    }
    # NOTE: this only applies where the targeted action supports resource-tag conditions
    # and the resource is already tagged; untagged resources are not caught by this
    # condition alone, so tagging-on-create policies / Config rules are still required.
  }

  # Deny disabling core security services (CloudTrail, Config, GuardDuty) - simulates
  # the "deny disabling security tooling" SCP every enterprise landing zone has
  statement {
    sid    = "DenyDisablingSecurityTooling"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "config:DeleteConfigRule",
      "config:DeleteConfigurationRecorder",
      "config:StopConfigurationRecorder",
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "securityhub:DisableSecurityHub",
    ]
    resources = ["*"]
  }

  # Deny leaving the lab's home region (cost + blast-radius control for a personal lab)
  statement {
    sid    = "DenyOutsideHomeRegion"
    effect = "Deny"
    actions = [
      "ec2:*",
      "rds:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = ["us-east-1"]
    }
  }
}

resource "aws_iam_policy" "boundary" {
  for_each    = toset(var.environments)
  name        = "boundary-${each.key}"
  description = "Permission boundary simulating an OU-level SCP for the ${each.key} environment"
  policy      = data.aws_iam_policy_document.boundary[each.key].json

  tags = merge(local.common_tags, { Environment = each.key })
}

# ---------- Assumable role per environment, with the boundary attached ----------
data "aws_iam_policy_document" "assume_role" {
  for_each = toset(var.environments)

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = var.trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "environment_role" {
  for_each             = toset(var.environments)
  name                 = "${each.key}-admin-role"
  assume_role_policy   = data.aws_iam_policy_document.assume_role[each.key].json
  permissions_boundary = aws_iam_policy.boundary[each.key].arn
  max_session_duration = 3600

  tags = merge(local.common_tags, { Environment = each.key })
}

resource "aws_iam_role_policy_attachment" "environment_role_admin" {
  for_each   = toset(var.environments)
  role       = aws_iam_role.environment_role[each.key].name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}
