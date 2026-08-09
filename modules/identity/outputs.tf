output "host_instance_profile_name" {
  description = "Name of the shared host IAM instance profile."
  value       = aws_iam_instance_profile.host.name
}

output "host_role_arn" {
  description = "ARN of the shared host IAM role."
  value       = aws_iam_role.host.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the managed GitHub Actions OIDC provider."
  value       = try(aws_iam_openid_connect_provider.github[0].arn, null)
}
