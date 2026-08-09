output "role_arns" {
  description = "Map of service names to deployment role ARNs."
  value       = { for name, role in aws_iam_role.service : name => role.arn }
}

