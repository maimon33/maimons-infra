terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Generate a random secret for the tunnel (must be 32+ bytes)
resource "random_password" "tunnel_secret" {
  length  = 32
  special = true
}

# Create the Cloudflare Tunnel using Zero Trust Tunnel API
resource "cloudflare_zero_trust_tunnel_cloudflared" "platform" {
  account_id    = var.cloudflare_account_id
  name          = var.tunnel_name
  tunnel_secret = random_password.tunnel_secret.result
}

# Get tunnel token via data source
data "cloudflare_zero_trust_tunnel_cloudflared_token" "platform" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.platform.id
}

# Store tunnel token in AWS Secrets Manager
resource "aws_secretsmanager_secret" "tunnel_token" {
  name                    = "maimons/cloudflare-tunnel-token"
  kms_key_id              = var.aws_secrets_manager_kms_key_arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tunnel_token" {
  secret_id     = aws_secretsmanager_secret.tunnel_token.id
  secret_string = data.cloudflare_zero_trust_tunnel_cloudflared_token.platform.token
}

# Store tunnel credentials for manual reference
resource "aws_secretsmanager_secret" "tunnel_config" {
  name                    = "maimons/cloudflare-tunnel-config"
  kms_key_id              = var.aws_secrets_manager_kms_key_arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tunnel_config" {
  secret_id = aws_secretsmanager_secret.tunnel_config.id
  secret_string = jsonencode({
    tunnel_id   = cloudflare_zero_trust_tunnel_cloudflared.platform.id
    account_id  = var.cloudflare_account_id
    tunnel_name = cloudflare_zero_trust_tunnel_cloudflared.platform.name
  })
}
