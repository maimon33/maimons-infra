output "data_volume_arn" {
  description = "ARN of the persistent application data volume."
  value       = aws_ebs_volume.application_data.arn
}

output "data_volume_id" {
  description = "ID of the persistent application data volume."
  value       = aws_ebs_volume.application_data.id
}

output "elastic_ip" {
  description = "Elastic IPv4 address assigned to the shared host."
  value       = aws_eip.host.public_ip
}

output "instance_arn" {
  description = "ARN of the shared EC2 instance."
  value       = aws_instance.host.arn
}

output "instance_id" {
  description = "ID of the shared EC2 instance."
  value       = aws_instance.host.id
}

