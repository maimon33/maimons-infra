variable "cloudflare_api_token" {
  description = "Cloudflare API token for authentication."
  type        = string
  sensitive   = true
}

variable "direct_origin_ip" {
  description = "Elastic IP used by proxied A records when Tunnel is disabled."
  type        = string
}

variable "manage_cache_rules" {
  description = "Whether to create the zone-level API cache bypass ruleset."
  type        = bool
  default     = true
}

variable "manage_zone_settings" {
  description = "Whether Terraform manages shared zone TLS and HTTPS settings."
  type        = bool
  default     = true
}

variable "sites" {
  description = "Approved public site catalog and Access configuration."
  type = map(object({
    access_emails = optional(set(string), [])
    access_path   = optional(string, "/admin")
    access_paths  = optional(map(list(string)), null)  # Path-based access: { "/path" = ["email1", "email2"] }
    hostname      = string
  }))
}

variable "tunnel_cname" {
  description = "Optional Cloudflare Tunnel CNAME target used instead of the direct origin address."
  type        = string
  default     = null
  nullable    = true
}

variable "zone_id" {
  description = "Cloudflare zone identifier."
  type        = string
}
