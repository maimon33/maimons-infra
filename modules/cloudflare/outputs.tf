output "access_application_ids" {
  description = "Map of site names to Cloudflare Access application IDs."
  value       = { for name, application in cloudflare_zero_trust_access_application.site : name => application.id }
}

output "dns_record_ids" {
  description = "Map of site names to Cloudflare DNS record IDs."
  value       = { for name, record in cloudflare_dns_record.site : name => record.id }
}
