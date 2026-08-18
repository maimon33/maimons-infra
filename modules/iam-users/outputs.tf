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
