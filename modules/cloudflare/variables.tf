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
    access_emails  = optional(set(string), [])
    access_path    = optional(string, "/admin")
    hostname      = string
  }))
}

variable "zone_id" {
  description = "Cloudflare zone identifier."
  type        = string
}
