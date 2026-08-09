output "security_group_id" {
  description = "ID of the shared host security group."
  value       = aws_security_group.host.id
}

output "subnet_id" {
  description = "ID of the public host subnet."
  value       = aws_subnet.public.id
}

output "vpc_id" {
  description = "ID of the platform VPC."
  value       = aws_vpc.platform.id
}

