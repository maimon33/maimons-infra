resource "cloudflare_zero_trust_access_application" "monitoring" {
  account_id = var.cloudflare_account_id
  name       = "Monitoring Dashboard"
  domain     = "monitor.maimons.dev"
  type       = "self_hosted"

  tags = ["monitoring", "platform"]
}

resource "cloudflare_dns_record" "monitoring" {
  zone_id  = var.cloudflare_zone_id
  name     = "monitor"
  type     = "CNAME"
  content  = module.cloudflare_tunnel.tunnel_cname
  ttl      = 3600
  proxied  = false
}

resource "cloudflare_dns_record" "mosar" {
  zone_id  = "92a1c8a20c71677cd317fdb47533b46d"
  name     = "mosar"
  type     = "CNAME"
  content  = module.cloudflare_tunnel.tunnel_cname
  ttl      = 3600
  proxied  = false
}

# Access policy created via API - uncomment when policy resource is available
# resource "cloudflare_access_policy" "monitoring_email" {
#   account_id     = var.cloudflare_account_id
#   application_id = cloudflare_zero_trust_access_application.monitoring.id
#   name           = "Allow maimon33@gmail.com"
#   precedence     = 1
#   decision       = "allow"
#   require = jsonencode({
#     email = {
#       email = ["maimon33@gmail.com"]
#     }
#   })
# }
