resource "cloudflare_dns_record" "site" {
  for_each = var.sites

  comment = "Managed by Terraform for ${each.key}"
  content = coalesce(var.tunnel_cname, var.direct_origin_ip)
  name    = each.value.hostname
  proxied = true
  ttl     = 1
  type    = var.tunnel_cname == null ? "A" : "CNAME"
  zone_id = var.zone_id
}

resource "cloudflare_zone_setting" "ssl" {
  count = var.manage_zone_settings ? 1 : 0

  setting_id = "ssl"
  value      = "flexible"
  zone_id    = var.zone_id
}

resource "cloudflare_zone_setting" "always_use_https" {
  count = var.manage_zone_settings ? 1 : 0

  setting_id = "always_use_https"
  value      = "on"
  zone_id    = var.zone_id
}

resource "cloudflare_zone_setting" "minimum_tls" {
  count = var.manage_zone_settings ? 1 : 0

  setting_id = "min_tls_version"
  value      = "1.2"
  zone_id    = var.zone_id
}

resource "cloudflare_zone_setting" "tls_1_3" {
  count = var.manage_zone_settings ? 1 : 0

  setting_id = "tls_1_3"
  value      = "on"
  zone_id    = var.zone_id
}

resource "cloudflare_zero_trust_access_application" "site" {
  for_each = {
    for key, site in var.sites : key => site
    if length(site.access_emails) > 0
  }

  domain                     = "${each.value.hostname}${each.value.access_path}"
  http_only_cookie_attribute = true
  name                       = "${each.key} ${each.value.access_path}"
  options_preflight_bypass   = true
  same_site_cookie_attribute = "lax"
  session_duration           = "24h"
  type                       = "self_hosted"
  zone_id                    = var.zone_id

  destinations = [{
    type = "public"
    uri  = "${each.value.hostname}${each.value.access_path}*"
  }]

  policies = [{
    decision   = "allow"
    include    = [for email_address in each.value.access_emails : { email = { email = email_address } }]
    name       = "Allowed users"
    precedence = 1
  }]
}

resource "cloudflare_ruleset" "api_cache_bypass" {
  count = var.manage_cache_rules ? 1 : 0

  description = "Never cache dynamic API or administrative requests"
  kind        = "zone"
  name        = "Maimons dynamic request cache policy"
  phase       = "http_request_cache_settings"
  zone_id     = var.zone_id

  rules = [
    for site in values(var.sites) : {
      action      = "set_cache_settings"
      description = "Bypass cache for ${site.hostname} API and admin paths"
      enabled     = true
      expression  = "(http.host eq \"${site.hostname}\" and (starts_with(http.request.uri.path, \"/api/\") or starts_with(http.request.uri.path, \"${site.access_path}\")))"
      action_parameters = {
        cache = false
      }
    }
  ]
}
