output "backup_vault_arn" {
  description = "ARN of the platform AWS Backup vault."
  value       = aws_backup_vault.platform.arn
}

output "backup_vault_name" {
  description = "Name of the platform AWS Backup vault."
  value       = aws_backup_vault.platform.name
}

