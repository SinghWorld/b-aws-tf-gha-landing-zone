variable "backup_tag_key" {
  description = "Tag key used to select resources for backup"
  type        = string
  default     = "Environment"
}

variable "backup_tag_value" {
  description = "Tag value used to select resources for backup (typically 'prod')"
  type        = string
  default     = "prod"
}

variable "schedule_expression" {
  description = "Cron expression for backup schedule (default: daily at 03:00 UTC)"
  type        = string
  default     = "cron(0 3 * * ? *)"
}

variable "retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 35
}

variable "tags" {
  description = "Tags to apply to backup resources"
  type        = map(string)
  default     = {}
}

locals {
  common_tags = merge(
    {
      ManagedBy = "terraform"
      Project   = "personal-landing-zone"
    },
    var.tags
  )
}

resource "aws_backup_vault" "this" {
  name = "personal-lab-backup-vault"
  tags = local.common_tags
}

resource "aws_iam_role" "backup" {
  name = "aws-backup-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "backup.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "backup_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "restore_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "this" {
  name = "personal-lab-backup-plan"

  rule {
    rule_name         = "daily-backups"
    target_vault_name = aws_backup_vault.this.name
    schedule          = var.schedule_expression

    lifecycle {
      delete_after = var.retention_days
    }
  }

  tags = local.common_tags
}

resource "aws_backup_selection" "this" {
  name         = "tag-based-selection"
  plan_id      = aws_backup_plan.this.id
  iam_role_arn = aws_iam_role.backup.arn

  selection_tag {
    type  = "STRINGEQUALS"
    key   = var.backup_tag_key
    value = var.backup_tag_value
  }
}
