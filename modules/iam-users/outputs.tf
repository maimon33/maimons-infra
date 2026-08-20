output "user_names" {
  description = "Map of service name -> IAM user name"
  value       = { for service in var.services : service => aws_iam_user.service_user[service].name }
}

output "user_arns" {
  description = "Map of service name -> IAM user ARN"
  value       = { for service in var.services : service => aws_iam_user.service_user[service].arn }
}

output "access_key_ids" {
  description = "Map of service name -> access key ID"
  value       = { for service in var.services : service => aws_iam_access_key.service_key[service].id }
  sensitive   = true
}

output "access_key_secrets" {
  description = "Map of service name -> secret access key"
  value       = { for service in var.services : service => aws_iam_access_key.service_key[service].secret }
  sensitive   = true
}

output "maimons_infra_user_name" {
  description = "Maimons-infra deployment IAM user name"
  value       = aws_iam_user.maimons_infra_user.name
}

output "maimons_infra_access_key_id" {
  description = "Maimons-infra deployment access key ID"
  value       = aws_iam_access_key.maimons_infra_key.id
  sensitive   = true
}

output "maimons_infra_access_key_secret" {
  description = "Maimons-infra deployment secret access key"
  value       = aws_iam_access_key.maimons_infra_key.secret
  sensitive   = true
}
