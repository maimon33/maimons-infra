variable "backup_bucket_arn" {
  description = "ARN of the centrally managed application backup bucket."
  type        = string
}

variable "ecr_repository_arns" {
  description = "Map of service names to ECR repository ARNs."
  type        = map(string)
  default     = {}
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the platform KMS key."
  type        = string
}

variable "manage_github_oidc_provider" {
  description = "Whether to create the account-wide GitHub Actions OIDC provider."
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "secret_arns" {
  description = "Map of logical service secret names to Secrets Manager ARNs."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}
