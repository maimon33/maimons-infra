variable "deployment_role_arns" {
  description = "Map of service names to deployment role ARNs."
  type        = map(string)
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "instance_id" {
  description = "ID of the shared EC2 instance."
  type        = string
}

variable "platform_values" {
  description = "Additional non-sensitive platform contract values."
  type        = map(string)
  default     = {}
}

variable "service_catalog" {
  description = "Approved service metadata published to SSM Parameter Store."
  type = map(object({
    health_path   = string
    hostname      = string
    internal_port = number
    service_name  = string
  }))
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}

