# DNS records for tunnel services
# Point each service hostname to the Cloudflare tunnel

locals {
  tunnel_id = "c2831ffb-2e97-4237-a86e-5ef2e0c3c10e"
  tunnel_cname = "${local.tunnel_id}.cfargotunnel.com"
}

# Create DNS records for each service
resource "cloudflare_dns_record" "services" {
  for_each = var.services

  zone_id = var.cloudflare_zone_id
  name    = each.value.hostname
  type    = "CNAME"
  content = local.tunnel_cname
  ttl     = 1  # Automatic TTL
}
