output "backup_bucket_arn" {
  description = "ARN of the application backup bucket."
  value       = aws_s3_bucket.backups.arn
}

output "backup_bucket_name" {
  description = "Name of the application backup bucket."
  value       = aws_s3_bucket.backups.id
}

output "ecr_repository_arns" {
  description = "Map of service names to ECR repository ARNs."
  value       = { for name, repository in aws_ecr_repository.service : name => repository.arn }
}

output "ecr_repository_urls" {
  description = "Map of service names to ECR repository URLs."
  value       = { for name, repository in aws_ecr_repository.service : name => repository.repository_url }
}

output "kms_key_arn" {
  description = "ARN of the platform KMS key."
  value       = aws_kms_key.platform.arn
}

output "secret_arns" {
  description = "Map of logical service secret names to Secrets Manager ARNs."
  value       = { for name, secret in aws_secretsmanager_secret.service : name => secret.arn }
}

