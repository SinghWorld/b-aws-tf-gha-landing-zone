locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "personal-landing-zone"
    },
    var.tags
  )
}

resource "aws_guardduty_detector" "this" {
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"

  tags = local.common_tags
}

resource "aws_securityhub_account" "this" {
  enable_default_standards = true
}

resource "aws_securityhub_standards_subscription" "cis" {
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.0"
  depends_on    = [aws_securityhub_account.this]
}

# CIS AWS Foundations conformance pack via Config - gives you the same
# detective-control baseline a Control Tower "Audit" account would enforce.
# Uses the AWS-managed sample template hosted by AWS in a public bucket so no
# manual template authoring is required. Verified path as of 2026; AWS
# occasionally relocates these - if the apply fails with a 404/access error,
# check https://docs.aws.amazon.com/config/latest/developerguide/conformancepack-sample-templates.html
# for the current S3 URI and update template_s3_uri below.
resource "aws_config_conformance_pack" "cis" {
  name            = "operational-best-practices-for-cis-aws-foundations-benchmark"
  template_s3_uri = "s3://aws-configservice-us-east-1/cloudformation-templates-for-managed-rules/Operational-Best-Practices-for-CIS-AWS-v1.4-Level1.yaml"
  delivery_s3_bucket = var.delivery_s3_bucket
}
