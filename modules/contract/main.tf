locals {
  platform_contract = merge(var.platform_values, {
    aws_region   = data.aws_region.current.region
    edge_network = "edge"
    instance_id  = var.instance_id
  })

  service_contract = merge([
    for service_key, service in var.service_catalog : {
      for field, value in service : "${service_key}/${field}" => tostring(value)
    }
  ]...)

  deployment_contract = {
    for service_key, role_arn in var.deployment_role_arns : "${service_key}/deploy_role_arn" => role_arn
  }
}

data "aws_region" "current" {}

resource "aws_ssm_parameter" "platform" {
  for_each = local.platform_contract

  description = "Published non-sensitive Maimons platform contract value"
  name        = "/platform/${var.environment}/${each.key}"
  overwrite   = true
  type        = "String"
  value       = each.value

  tags = var.tags
}

resource "aws_ssm_parameter" "service" {
  for_each = merge(local.service_contract, local.deployment_contract)

  description = "Published non-sensitive Maimons service contract value"
  name        = "/platform/${var.environment}/sites/${each.key}"
  overwrite   = true
  type        = "String"
  value       = each.value

  tags = var.tags
}

