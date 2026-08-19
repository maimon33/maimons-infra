locals {
  common_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Project     = var.project_name
  }

  cloudflare_sites = {
    for name, service in var.services : name => {
      access_emails = service.access_emails
      access_path   = service.access_path
      access_paths  = lookup(service, "access_paths", null)  # Optional path-based access
      hostname      = service.hostname
    }
  }

  service_catalog = {
    for name, service in var.services : name => {
      health_path   = service.health_path
      hostname      = service.hostname
      internal_port = service.internal_port
      service_name  = service.service_name
    }
  }

  name_prefix = var.project_name
  environment = var.environment
  services    = ["mosar", "monitoring"]
}
