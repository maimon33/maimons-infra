output "parameter_arns" {
  description = "ARNs of published platform and service contract parameters."
  value = concat(
    [for parameter in aws_ssm_parameter.platform : parameter.arn],
    [for parameter in aws_ssm_parameter.service : parameter.arn],
  )
}

