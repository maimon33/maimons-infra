variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Tunnel permissions."
  type        = string
  sensitive   = true
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel."
  type        = string
  default     = "maimons-platform"
}

variable "aws_region" {
  description = "AWS region for storing tunnel credentials."
  type        = string
}

variable "aws_secrets_manager_kms_key_arn" {
  description = "KMS key ARN for encrypting secrets in Secrets Manager."
  type        = string
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}
