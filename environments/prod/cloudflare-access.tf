resource "cloudflare_zero_trust_access_application" "monitoring" {
  account_id       = var.cloudflare_account_id
  name             = "Monitoring Dashboard"
  domain           = "monitor.maimons.dev"
  type             = "self_hosted"
  session_duration = "720h"

  tags = ["monitoring", "platform"]
}

resource "cloudflare_dns_record" "monitoring" {
  zone_id  = var.cloudflare_zone_id
  name     = "monitor"
  type     = "CNAME"
  content  = module.cloudflare_tunnel.tunnel_cname
  ttl      = 1
  proxied  = true
}

resource "cloudflare_dns_record" "mosar" {
  zone_id  = "92a1c8a20c71677cd317fdb47533b46d"
  name     = "mosar"
  type     = "CNAME"
  content  = module.cloudflare_tunnel.tunnel_cname
  ttl      = 1
  proxied  = true
}

