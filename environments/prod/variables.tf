variable "alarm_email_addresses" {
  description = "Email addresses subscribed to platform alarm notifications."
  type        = set(string)
  default     = []
}

variable "ami_id" {
  description = "AMI ID of the existing shared EC2 instance."
  type        = string
}

variable "availability_zone" {
  description = "Availability Zone containing the existing EC2 instance."
  type        = string
  default     = "eu-central-1a"
}

variable "aws_region" {
  description = "AWS region containing the shared platform."
  type        = string
  default     = "eu-central-1"
}

variable "backup_bucket_name" {
  description = "Globally unique name of the existing or new application backup bucket."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone identifier."
  type        = string
  sensitive   = true
}

variable "data_volume_size" {
  description = "Size in GiB of the persistent application data volume."
  type        = number
  default     = 100
}

variable "deployment_principal_arns" {
  description = "Map of service names to AWS principals allowed to assume deployment roles."
  type        = map(set(string))
  default     = {}
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "github_repository_subjects" {
  description = "Map of service names to allowed GitHub Actions OIDC subject claims."
  type        = map(set(string))
  default     = {}
}

variable "instance_type" {
  description = "EC2 instance type for the shared host."
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Optional EC2 key pair retained for emergency access."
  type        = string
  default     = null
  nullable    = true
}

variable "manage_cloudflare_cache_rules" {
  description = "Whether Terraform manages the zone-level dynamic request cache bypass."
  type        = bool
  default     = true
}

variable "manage_cloudflare_zone_settings" {
  description = "Whether Terraform manages shared zone TLS settings."
  type        = bool
  default     = true
}

variable "manage_github_oidc_provider" {
  description = "Whether Terraform creates the account-wide GitHub Actions OIDC provider."
  type        = bool
  default     = true
}

variable "project_name" {
  description = "Project name used in resource names and tags."
  type        = string
  default     = "maimons-infra"
}

variable "root_volume_size" {
  description = "Size in GiB of the shared host root volume."
  type        = number
  default     = 30
}

variable "service_secret_names" {
  description = "Logical names of Secrets Manager containers created without values."
  type        = set(string)
  default     = []
}

variable "services" {
  description = "Approved central service catalog."
  type = map(object({
    access_emails = optional(set(string), [])
    access_path   = optional(string, "/admin")
    health_path   = string
    hostname      = string
    internal_port = number
    service_name  = string
  }))

  validation {
    condition = alltrue([
      for service in values(var.services) : service.internal_port >= 1 && service.internal_port <= 65535
    ])
    error_message = "Every service internal_port must be between 1 and 65535."
  }
}

variable "ssh_ipv4_cidrs" {
  description = "Temporary operator IPv4 CIDRs allowed to use SSH; keep empty after SSM is verified."
  type        = set(string)
  default     = []
}

variable "subnet_cidr" {
  description = "CIDR of the public host subnet."
  type        = string
  default     = "10.33.1.0/24"
}

variable "vpc_cidr" {
  description = "CIDR of the platform VPC."
  type        = string
  default     = "10.33.0.0/16"
}
