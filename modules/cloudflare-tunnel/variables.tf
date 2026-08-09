variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Tunnel permissions."
  type        = string
  sensitive   = true
}

variable "ingress_services" {
  description = "Map of public hostnames to app URLs reachable by cloudflared on the host."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for service_url in values(var.ingress_services) : can(regex("^https?://", service_url))
    ])
    error_message = "Every ingress service URL must use HTTP or HTTPS."
  }
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
