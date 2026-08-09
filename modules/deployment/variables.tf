variable "deployment_principal_arns" {
  description = "Map of service names to AWS principal ARNs allowed to assume deployment roles."
  type        = map(set(string))
  default     = {}
}

variable "ecr_repository_arns" {
  description = "Map of service names to ECR repository ARNs."
  type        = map(string)
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider used by deployment roles."
  type        = string
  default     = null
  nullable    = true
}

variable "github_repository_subjects" {
  description = "Map of service names to allowed GitHub OIDC subject claims."
  type        = map(set(string))
  default     = {}
}

variable "instance_arn" {
  description = "ARN of the shared EC2 instance targeted by SSM deployments."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}
