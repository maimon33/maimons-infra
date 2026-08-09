output "alarm_topic_arn" {
  description = "ARN of the SNS topic used for platform alarms."
  value       = aws_sns_topic.platform.arn
}

output "dashboard_name" {
  description = "Name of the shared platform CloudWatch dashboard."
  value       = aws_cloudwatch_dashboard.platform.dashboard_name
}

output "log_group_name" {
  description = "Name of the central platform CloudWatch log group."
  value       = aws_cloudwatch_log_group.platform.name
}

