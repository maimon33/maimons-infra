module "cloudflare_tunnel" {
  source = "../../modules/cloudflare-tunnel"

  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  ingress_services = {
    for service in values(var.services) : service.hostname => "http://127.0.0.1:${service.internal_port}"
  }
  aws_region                      = var.aws_region
  aws_secrets_manager_kms_key_arn = module.data.kms_key_arn
  tags                            = local.common_tags
}
