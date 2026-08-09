variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt the AWS Backup vault."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "resource_arns" {
  description = "ARNs of EC2 and EBS resources protected by AWS Backup."
  type        = list(string)
}

variable "retention_days" {
  description = "Number of days recovery points remain in the AWS Backup vault."
  type        = number
  default     = 35
}

variable "schedule" {
  description = "EventBridge cron expression for the daily backup window."
  type        = string
  default     = "cron(0 2 * * ? *)"
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}

