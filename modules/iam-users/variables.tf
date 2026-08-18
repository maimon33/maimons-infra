variable "name_prefix" {
  description = "Resource naming prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, staging, etc)"
  type        = string
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
}

variable "services" {
  description = "List of services requiring IAM users"
  type        = list(string)
  default     = ["mosar", "monitoring"]
}

variable "kms_key_arn" {
  description = "Platform KMS key ARN (for policy statements)"
  type        = string
}

variable "s3_backup_bucket_arn" {
  description = "S3 backup bucket ARN"
  type        = string
}

variable "ecr_repository_arns" {
  description = "Map of service name -> ECR repository ARN"
  type        = map(string)
}

variable "secret_arns" {
  description = "Map of service name -> Secrets Manager secret ARN"
  type        = map(string)
}
