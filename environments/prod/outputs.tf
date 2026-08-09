output "backup_bucket_name" {
  description = "Name of the central application backup bucket."
  value       = module.data.backup_bucket_name
}

output "deployment_role_arns" {
  description = "Map of service names to deployment role ARNs."
  value       = module.deployment.role_arns
}

output "ecr_repository_urls" {
  description = "Map of service names to ECR repository URLs."
  value       = module.data.ecr_repository_urls
}

output "cloudflare_tunnel_cname" {
  description = "CNAME record for Cloudflare Tunnel (for manual DNS setup)."
  value       = module.cloudflare_tunnel.tunnel_cname
}

output "cloudflare_tunnel_id" {
  description = "Cloudflare Tunnel ID for service routing."
  value       = module.cloudflare_tunnel.tunnel_id
}

output "cloudflare_tunnel_token_secret_arn" {
  description = "ARN of the secret storing the tunnel token."
  value       = module.cloudflare_tunnel.tunnel_token_secret_arn
}

output "elastic_ip" {
  description = "Elastic IP assigned to direct Cloudflare ingress."
  value       = module.compute.elastic_ip
}

output "instance_id" {
  description = "ID of the shared EC2 host."
  value       = module.compute.instance_id
}

