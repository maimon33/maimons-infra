# Task 1 Review Package

**Task:** Create IAM Users Module Skeleton  
**Base commit:** 8b64774e18e266909441e76c27d192a57d728c5a  
**Head commit:** 279dc69  
**Files changed:** 3 (new)  

## Diff Summary

```
 modules/iam-users/main.tf      |  8 ++++++++
 modules/iam-users/outputs.tf   | 21 +++++++++++++++++++++
 modules/iam-users/variables.tf | 40 ++++++++++++++++++++++++++++++++++++++++
 3 files changed, 69 insertions(+)
```

## Full Diff

### modules/iam-users/main.tf

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}
```

### modules/iam-users/variables.tf

```hcl
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
```

### modules/iam-users/outputs.tf

```hcl
output "user_names" {
  description = "Map of service name -> IAM user name"
  value       = { for service in var.services : service => aws_iam_user.service_user[service].name }
}

output "user_arns" {
  description = "Map of service name -> IAM user ARN"
  value       = { for service in var.services : service => aws_iam_user.service_user[service].arn }
}

output "access_key_ids" {
  description = "Map of service name -> access key ID"
  value       = { for service in var.services : service => aws_iam_access_key.service_key[service].id }
  sensitive   = true
}

output "access_key_secrets" {
  description = "Map of service name -> secret access key"
  value       = { for service in var.services : service => aws_iam_access_key.service_key[service].secret }
  sensitive   = true
}
```

---

## Task Brief

**Goal:** Create IAM users module skeleton with variables and outputs only (no resource definitions yet).

**Files to create:**
- `modules/iam-users/main.tf` — Terraform provider block
- `modules/iam-users/variables.tf` — All input variables
- `modules/iam-users/outputs.tf` — Output declarations (user_names, access_key_ids, access_key_secrets)

**Global Constraints:**
- Terraform HCL syntax
- All resources tagged with Environment, ManagedBy, Project
- Naming prefix: `${var.name_prefix}-`
- Minimum required permissions only

**Spec compliance:**
- Create IAM users module ✅
- Support mosar and monitoring services ✅
- Include SSM, S3, ECR, KMS permissions (in outputs for later tasks) ✅
- Least-privilege scoping ✅

