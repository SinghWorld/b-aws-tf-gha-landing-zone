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
  standards_arn = "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/3.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# CIS AWS Foundations conformance pack via Config - gives you the same
# detective-control baseline a Control Tower "Audit" account would enforce.
# CIS Conformance Pack — deferred to post-apply CLI
# The AWS S3 path for sample conformance pack templates is periodically relocated by
# AWS and becomes inaccessible. For a lab, create this manually after apply:
#
#   aws configservice put-conformance-pack \
#     --conformance-pack-name operational-best-practices-for-cis-aws-foundations-benchmark \
#     --template-body https://raw.githubusercontent.com/awslabs/aws-config-rules/master/aws-config-conformance-packs/Operational-Best-Practices-for-CIS-AWS-v1.4-Level1.yaml \
#     --delivery-s3-bucket YOUR_DELIVERY_BUCKET
#
# Security Hub CIS subscription (v3.0.0) is applied via Terraform and provides the
# same security benchmark visibility even without the Config conformance pack.
