output "guardduty_detector_id" {
  description = "ID of the GuardDuty detector"
  value       = aws_guardduty_detector.this.id
}

output "conformance_pack_arn" {
  description = "ARN of the CIS conformance pack"
  value       = aws_config_conformance_pack.cis.arn
}
