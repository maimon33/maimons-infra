output "tunnel_id" {
  description = "Cloudflare Tunnel ID."
  value       = cloudflare_zero_trust_tunnel_cloudflared.platform.id
}

output "tunnel_cname" {
  description = "CNAME record for tunnel (for manual DNS setup)."
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.platform.id}.cfargotunnel.com"
}

output "tunnel_token_secret_arn" {
  description = "ARN of the secret storing the tunnel token in Secrets Manager."
  value       = aws_secretsmanager_secret.tunnel_token.arn
}

output "tunnel_config_secret_arn" {
  description = "ARN of the secret storing tunnel configuration."
  value       = aws_secretsmanager_secret.tunnel_config.arn
}
