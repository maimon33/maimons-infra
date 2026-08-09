variable "backup_bucket_name" {
  description = "Globally unique S3 bucket name for application backups and media."
  type        = string
}

variable "backup_retention_days" {
  description = "Days after which noncurrent backup object versions are expired."
  type        = number
  default     = 365
}

variable "ecr_repository_names" {
  description = "Names of ECR repositories managed for platform services."
  type        = set(string)
  default     = []
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "secret_names" {
  description = "Logical names of empty Secrets Manager containers; secret values are populated separately."
  type        = set(string)
  default     = []
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}

