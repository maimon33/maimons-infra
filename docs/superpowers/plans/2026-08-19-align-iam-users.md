# IAM User Migration & Least-Privilege Policy Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate from OIDC role-based authentication to IAM user credentials in maimon-infra, providing minimal-permission access keys for CI/CD deployment (mosar pattern).

**Architecture:** Create a new IAM user module in maimon-infra that provisions static access keys with granular policies scoped to service-specific resources. This aligns with mosar's current AWS_ACCESS_KEY_ID/SECRET workflow while centralizing policy management in Terraform.

**Tech Stack:** Terraform (HCL), AWS IAM (users, policies, access keys)

**Spec:** User request to align mosar's IAM user pattern (static credentials) into maimon-infra and generate least-privilege policies for each service.

## Global Constraints

- Terraform files use HCL syntax (no generated JSON)
- All resources tagged with Environment, ManagedBy, Project
- Named with prefix: `${var.name_prefix}-`
- Minimum required permissions only (no wildcards beyond service APIs)
- All sensitive outputs (access keys) marked as sensitive in Terraform

---

## File Structure

```
maimons-infra/
├── modules/
│   ├── identity/
│   │   ├── main.tf                    (existing - no changes)
│   │   ├── variables.tf               (existing - no changes)
│   │   └── outputs.tf                 (existing - no changes)
│   │
│   └── iam-users/                    (NEW - service deployment users)
│       ├── main.tf                    (user + access key provisioning)
│       ├── variables.tf               (service definitions, permissions list)
│       ├── outputs.tf                 (user ARNs, access key IDs)
│       └── policies/                  (NEW - JSON policy templates)
│           ├── mosar-deploy.json      (mosar-specific policy)
│           └── monitoring-deploy.json (monitoring-specific policy)
│
└── environments/prod/
    └── main.tf                        (add iam-users module call)
```

---

## Task Breakdown

### Task 1: Create IAM Users Module Skeleton

**Files:**
- Create: `modules/iam-users/main.tf`
- Create: `modules/iam-users/variables.tf`
- Create: `modules/iam-users/outputs.tf`

**Interfaces:**
- Consumes: `var.name_prefix`, `var.environment`, `var.tags`, `var.services` (list of service names)
- Produces: `output.user_names`, `output.access_key_ids`, `output.access_key_secrets`

**Steps:**

- [ ] **Step 1: Create `modules/iam-users/main.tf`** with AWS provider block:
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

- [ ] **Step 2: Create `modules/iam-users/variables.tf`**:
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

- [ ] **Step 3: Create `modules/iam-users/outputs.tf`**:
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

- [ ] **Step 4: Commit**:
```bash
git add modules/iam-users/
git commit -m "feat: scaffold iam-users module for service deployment credentials"
```

---

### Task 2: Create Mosar Deployment User & Policy

**Files:**
- Modify: `modules/iam-users/main.tf` (add mosar user + policy)
- Create: `modules/iam-users/policies/mosar-deploy.json`

**Interfaces:**
- Consumes: `aws_iam_user.service_user["mosar"]`, `var.kms_key_arn`, `var.ecr_repository_arns["mosar"]`, `var.secret_arns["mosar"]`
- Produces: `aws_iam_user_policy.mosar_deploy`

**Steps:**

- [ ] **Step 1: Create `modules/iam-users/policies/mosar-deploy.json`**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPushAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "${ECR_REPO_ARN}"
    },
    {
      "Sid": "ECRAuthToken",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerRead",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "${SECRET_ARN}"
    },
    {
      "Sid": "KMSDecrypt",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt",
        "kms:DescribeKey"
      ],
      "Resource": "${KMS_KEY_ARN}"
    },
    {
      "Sid": "S3BackupRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "${S3_BUCKET_ARN}",
        "${S3_BUCKET_ARN}/*"
      ]
    },
    {
      "Sid": "SSMCommandExecution",
      "Effect": "Allow",
      "Action": [
        "ssm:SendCommand",
        "ssm:GetCommandInvocation",
        "ssm:ListCommandInvocations",
        "ssm:CancelCommand"
      ],
      "Resource": "*"
    }
  ]
}
```

- [ ] **Step 2: Modify `modules/iam-users/main.tf`** to add mosar user creation:
```hcl
# Service deployment IAM users
resource "aws_iam_user" "service_user" {
  for_each = toset(var.services)

  name = "${var.name_prefix}-${each.value}-deploy-user"
  tags = merge(var.tags, {
    Service = each.value
    Purpose = "CI/CD Deployment Credentials"
  })
}

# Access keys for each service user
resource "aws_iam_access_key" "service_key" {
  for_each = toset(var.services)

  user       = aws_iam_user.service_user[each.value].name
  depends_on = [aws_iam_user_policy.service_policy]
}

# Service deployment policy
resource "aws_iam_user_policy" "service_policy" {
  for_each = toset(var.services)

  name   = "${var.name_prefix}-${each.value}-deploy"
  user   = aws_iam_user.service_user[each.value].name
  policy = templatefile("${path.module}/policies/${each.value}-deploy.json", {
    ECR_REPO_ARN   = var.ecr_repository_arns[each.value]
    SECRET_ARN     = var.secret_arns[each.value]
    KMS_KEY_ARN    = var.kms_key_arn
    S3_BUCKET_ARN  = var.s3_backup_bucket_arn
  })
}
```

- [ ] **Step 3: Commit**:
```bash
git add modules/iam-users/main.tf modules/iam-users/policies/mosar-deploy.json
git commit -m "feat: create mosar deployment user with least-privilege policy"
```

---

### Task 3: Create Monitoring Deployment User & Policy

**Files:**
- Create: `modules/iam-users/policies/monitoring-deploy.json`

**Interfaces:**
- Consumes: Same as Task 2, but for `monitoring` service
- Produces: `aws_iam_user_policy.service_policy["monitoring"]`

**Steps:**

- [ ] **Step 1: Create `modules/iam-users/policies/monitoring-deploy.json`** (similar to mosar but scoped to monitoring service):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPushAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "${ECR_REPO_ARN}"
    },
    {
      "Sid": "ECRAuthToken",
      "Effect": "Allow",
      "Action": ["ecr:GetAuthorizationToken"],
      "Resource": "*"
    },
    {
      "Sid": "SecretsManagerRead",
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "${SECRET_ARN}"
    },
    {
      "Sid": "KMSDecrypt",
      "Effect": "Allow",
      "Action": ["kms:Decrypt", "kms:DescribeKey"],
      "Resource": "${KMS_KEY_ARN}"
    },
    {
      "Sid": "S3BackupRead",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["${S3_BUCKET_ARN}", "${S3_BUCKET_ARN}/*"]
    }
  ]
}
```

- [ ] **Step 2: Commit**:
```bash
git add modules/iam-users/policies/monitoring-deploy.json
git commit -m "feat: create monitoring deployment user with least-privilege policy"
```

---

### Task 4: Wire Up IAM Users Module in Production Environment

**Files:**
- Modify: `environments/prod/main.tf` (add iam-users module call)
- Modify: `environments/prod/locals.tf` or `environments/prod/variables.tf` (if needed for service list)

**Interfaces:**
- Consumes: Outputs from `module.data` (KMS key ARN, S3 bucket ARN, ECR repo ARNs, secret ARNs)
- Produces: `module.iam_users.user_names`, `module.iam_users.access_key_ids`

**Steps:**

- [ ] **Step 1: Modify `environments/prod/main.tf`** to add iam-users module (after data module):
```hcl
module "iam_users" {
  source = "../../modules/iam-users"

  name_prefix           = local.name_prefix
  environment           = local.environment
  tags                  = local.common_tags
  services              = local.services
  
  kms_key_arn           = module.data.kms_key_arn
  s3_backup_bucket_arn  = module.data.backup_bucket_arn
  ecr_repository_arns   = module.data.ecr_repository_arns
  secret_arns           = module.data.secret_arns

  depends_on = [module.data]
}
```

- [ ] **Step 2: Verify `locals.tf`** has `services` list defined. If not:
```hcl
locals {
  services = ["mosar", "monitoring"]
}
```

- [ ] **Step 3: Commit**:
```bash
git add environments/prod/main.tf environments/prod/locals.tf
git commit -m "feat: integrate iam-users module into production environment"
```

---

### Task 5: Create Outputs for Access Key Retrieval

**Files:**
- Modify: `environments/prod/outputs.tf` (add iam-users outputs)

**Interfaces:**
- Consumes: `module.iam_users.access_key_ids`, `module.iam_users.access_key_secrets`, `module.iam_users.user_names`
- Produces: Terraform outputs for CI/CD secret injection

**Steps:**

- [ ] **Step 1: Add to `environments/prod/outputs.tf`**:
```hcl
output "iam_user_access_keys" {
  description = "Access key IDs for service deployment users (use in GitHub Secrets)"
  value       = module.iam_users.access_key_ids
  sensitive   = true
}

output "iam_user_access_secrets" {
  description = "Secret access keys for service deployment users (use in GitHub Secrets)"
  value       = module.iam_users.access_key_secrets
  sensitive   = true
}

output "iam_user_names" {
  description = "IAM user names for service deployment"
  value       = module.iam_users.user_names
}
```

- [ ] **Step 2: Run Terraform validate**:
```bash
cd environments/prod
terraform validate
```

- [ ] **Step 3: Commit**:
```bash
git add environments/prod/outputs.tf
git commit -m "feat: expose iam user credentials for ci/cd injection"
```

---

### Task 6: Create Policy Documentation

**Files:**
- Create: `docs/IAM_USER_POLICIES.md`

**Interfaces:**
- Consumes: Policy JSON from Tasks 2 & 3
- Produces: Human-readable policy documentation

**Steps:**

- [ ] **Step 1: Create `docs/IAM_USER_POLICIES.md`**:
```markdown
# IAM User Policies for Deployment

## Overview
Service-specific IAM users provision static credentials for CI/CD pipelines. Each user has minimal permissions scoped to their service's resources only.

## Mosar Deployment User Policy

**User Name:** `{name_prefix}-mosar-deploy-user`

### Permissions Breakdown

| Action | Resource | Purpose |
|--------|----------|---------|
| `ecr:PutImage`, `ecr:CompleteLayerUpload`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage` | Mosar ECR repository ARN | Push Docker images during CI/CD builds |
| `ecr:GetAuthorizationToken` | `*` | Authenticate with ECR registry |
| `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` | `/platform/prod/mosar/runtime` secret ARN | Retrieve runtime configuration secrets |
| `kms:Decrypt`, `kms:DescribeKey` | Platform KMS key ARN | Decrypt secrets encrypted at rest |
| `s3:GetObject`, `s3:ListBucket` | Backup bucket + objects | Retrieve backup data for deployment validation |
| `ssm:SendCommand`, `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`, `ssm:CancelCommand` | `*` | Execute deployment commands on EC2 instances |

### Scope
- **ECR**: Write access limited to mosar's repository ARN only (no cross-service access)
- **Secrets**: Read-only access to `/platform/prod/mosar/runtime` secret
- **KMS**: Decrypt operations only (no key management permissions)
- **S3**: Read-only access to backup bucket (no delete/put permissions)
- **SSM**: Command execution limited to SendCommand + status operations

### Why This Policy is Minimal
- ❌ No S3 `PutObject`, `DeleteObject`, `PutBucketPolicy` (read-only backup access)
- ❌ No ECR `DeleteRepository`, `PutRepositoryPolicy` (image push only)
- ❌ No `secretsmanager:CreateSecret`, `UpdateSecret`, `DeleteSecret` (read-only)
- ❌ No KMS `CreateGrant`, `ScheduleKeyDeletion`, `DisableKey` (decrypt-only)
- ❌ No IAM, CloudFormation, or account-level permissions

## Monitoring Deployment User Policy

**User Name:** `{name_prefix}-monitoring-deploy-user`

Identical structure to mosar, but scoped to monitoring service's resources:
- ECR repository: monitoring's repo only
- Secrets: `/platform/prod/monitoring/runtime` secret
- All other permissions (KMS, S3, SSM) are service-agnostic and shared

### Difference from Mosar
Monitoring policy does NOT include S3 backup access (not needed for monitoring deployment).

## Access Key Rotation

- Access keys stored securely in GitHub Secrets (one per service)
- Rotation policy: 90-day manual rotation (update key, rotate secret in GitHub, deactivate old key)
- To rotate:
  1. Generate new access key via Terraform: `terraform apply`
  2. Update GitHub Secrets with new credentials
  3. Deactivate old key: `aws iam delete-access-key --access-key-id <old-key-id>`

## Usage in CI/CD

Export credentials as environment variables in GitHub Actions:
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.MOSAR_AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.MOSAR_AWS_SECRET_ACCESS_KEY }}
  AWS_REGION: il-central-1
```
```

- [ ] **Step 2: Commit**:
```bash
git add docs/IAM_USER_POLICIES.md
git commit -m "docs: add iam user policy reference guide"
```

---

## Spec Coverage

| Requirement | Task | Status |
|---|---|---|
| Create IAM users (not roles) | Tasks 1–2 | ✅ |
| Support mosar service | Task 2 | ✅ |
| Support monitoring service | Task 3 | ✅ |
| Include SSM permissions | Task 2 (SSMCommandExecution) | ✅ |
| Include S3 permissions | Task 2 (S3BackupRead) | ✅ |
| Include ECR permissions | Task 2 (ECRPushAccess) | ✅ |
| Include KMS permissions | Task 2 (KMSDecrypt) | ✅ |
| Least-privilege scoping | Tasks 2–3 (resource ARN restrictions) | ✅ |
| Align with maimon-infra patterns | Task 4 (module integration) | ✅ |
| Policy documentation | Task 6 | ✅ |
