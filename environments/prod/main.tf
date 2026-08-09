data "cloudflare_ip_ranges" "cloudflare" {}

module "data" {
  source = "../../modules/data"

  backup_bucket_name   = var.backup_bucket_name
  ecr_repository_names = toset(keys(var.services))
  environment          = var.environment
  name_prefix          = var.project_name
  secret_names         = var.service_secret_names
  tags                 = local.common_tags
}

module "identity" {
  source = "../../modules/identity"

  backup_bucket_arn           = module.data.backup_bucket_arn
  ecr_repository_arns         = module.data.ecr_repository_arns
  environment                 = var.environment
  kms_key_arn                 = module.data.kms_key_arn
  manage_github_oidc_provider = var.manage_github_oidc_provider
  name_prefix                 = var.project_name
  secret_arns                 = module.data.secret_arns
  tags                        = local.common_tags
}

module "network" {
  source = "../../modules/network"

  availability_zone     = var.availability_zone
  cloudflare_ipv4_cidrs = toset(data.cloudflare_ip_ranges.cloudflare.ipv4_cidrs)
  cloudflare_ipv6_cidrs = toset(data.cloudflare_ip_ranges.cloudflare.ipv6_cidrs)
  environment           = var.environment
  name_prefix           = var.project_name
  ssh_ipv4_cidrs        = var.ssh_ipv4_cidrs
  subnet_cidr           = var.subnet_cidr
  tags                  = local.common_tags
  vpc_cidr              = var.vpc_cidr
}

module "compute" {
  source = "../../modules/compute"

  ami_id                = var.ami_id
  availability_zone     = var.availability_zone
  data_volume_size      = var.data_volume_size
  environment           = var.environment
  instance_profile_name = module.identity.host_instance_profile_name
  instance_type         = var.instance_type
  key_name              = var.key_name
  kms_key_arn           = module.data.kms_key_arn
  name_prefix           = var.project_name
  root_volume_size      = var.root_volume_size
  security_group_ids    = [module.network.security_group_id]
  subnet_id             = module.network.subnet_id
  tags                  = local.common_tags
}

module "deployment" {
  source = "../../modules/deployment"

  deployment_principal_arns  = var.deployment_principal_arns
  ecr_repository_arns        = module.data.ecr_repository_arns
  environment                = var.environment
  github_oidc_provider_arn   = module.identity.github_oidc_provider_arn
  github_repository_subjects = var.github_repository_subjects
  instance_arn               = module.compute.instance_arn
  name_prefix                = var.project_name
  tags                       = local.common_tags
}

module "backup" {
  source = "../../modules/backup"

  environment   = var.environment
  kms_key_arn   = module.data.kms_key_arn
  name_prefix   = var.project_name
  resource_arns = [module.compute.instance_arn, module.compute.data_volume_arn]
  tags          = local.common_tags
}

module "observability" {
  source = "../../modules/observability"

  alarm_email_addresses = var.alarm_email_addresses
  environment           = var.environment
  instance_id           = module.compute.instance_id
  name_prefix           = var.project_name
  tags                  = local.common_tags
}

module "cloudflare" {
  source = "../../modules/cloudflare"

  direct_origin_ip     = module.compute.elastic_ip
  manage_cache_rules   = var.manage_cloudflare_cache_rules
  manage_zone_settings = var.manage_cloudflare_zone_settings
  sites                = local.cloudflare_sites
  zone_id              = var.cloudflare_zone_id
}

module "contract" {
  source = "../../modules/contract"

  deployment_role_arns = module.deployment.role_arns
  environment          = var.environment
  instance_id          = module.compute.instance_id
  platform_values = {
    backup_bucket = module.data.backup_bucket_name
  }
  service_catalog = local.service_catalog
  tags            = local.common_tags
}
