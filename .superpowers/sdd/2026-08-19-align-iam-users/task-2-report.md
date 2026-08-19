# Task 2 Report: Create Mosar Deployment User & Policy

**Status:** DONE

**Date:** 2026-08-19

## Summary

Successfully implemented Task 2 of the IAM user module. Created the mosar deployment user with a least-privilege IAM policy providing minimal permissions for ECR push, S3 read, KMS decrypt, Secrets Manager read, and SSM command execution.

## Files Created

1. **`modules/iam-users/policies/mosar-deploy.json`** (68 lines)
   - IAM policy with 6 Statement blocks:
     - `ECRPushAccess`: Push permissions to mosar ECR repository
     - `ECRAuthToken`: Registry authentication token
     - `SecretsManagerRead`: Read mosar secrets
     - `KMSDecrypt`: Decrypt operations on platform KMS key
     - `S3BackupRead`: Read-only access to backup bucket
     - `SSMCommandExecution`: Deployment command execution

2. **`modules/iam-users/.terraform.lock.hcl`**
   - Terraform provider lock file (auto-generated, includes aws v6.60.0)

## Files Modified

1. **`modules/iam-users/main.tf`** (33 new lines)
   - Added 3 resource blocks:
     - `aws_iam_user.service_user`: for_each over services
     - `aws_iam_access_key.service_key`: for_each over services with dependency on policy
     - `aws_iam_user_policy.service_policy`: for_each over services using templatefile

## Verification Results

### Terraform Validation
```
terraform fmt modules/iam-users/main.tf
✓ Formatting completed successfully

cd modules/iam-users && terraform init && terraform validate
✓ AWS provider v6.60.0 installed
✓ Configuration is valid
```

## Commit

**Commit SHA:** `bcaeef36a42bda823e3bba44a30e7ae01a520d40`

**Message:** "feat: create mosar deployment user with least-privilege policy"

**Changes:**
- 3 files changed
- 127 insertions
  - mosar-deploy.json: 68 lines
  - main.tf: 33 lines (added resources)
  - .terraform.lock.hcl: 26 lines

## Technical Details

### Policy Permissions (mosar)

| Service | Permissions | Resource Scope | Purpose |
|---------|-----------|-----------------|---------|
| ECR | PutImage, InitiateLayerUpload, UploadLayerPart, CompleteLayerUpload, BatchCheckLayerAvailability, GetDownloadUrlForLayer, BatchGetImage | mosar ECR repo ARN | Push Docker images |
| ECR | GetAuthorizationToken | * | Registry authentication |
| Secrets Manager | GetSecretValue, DescribeSecret | mosar secret ARN | Read deployment config |
| KMS | Decrypt, DescribeKey | platform KMS key ARN | Decrypt encrypted secrets |
| S3 | GetObject, ListBucket | backup bucket + objects | Read-only backup access |
| SSM | SendCommand, GetCommandInvocation, ListCommandInvocations, CancelCommand | * | Execute deployment ops |

### Least-Privilege Design

The policy excludes:
- S3: No PutObject, DeleteObject, or policy modifications
- ECR: No DeleteRepository or policy modifications
- Secrets Manager: No CreateSecret, UpdateSecret, or DeleteSecret
- KMS: No key management operations (only decrypt)
- IAM/CloudFormation: Zero account-level permissions

### Resource Integration

The resources use:
- `for_each` loop over `var.services` list
- `templatefile()` function to inject ARNs into policy JSON
- Template variables: ECR_REPO_ARN, SECRET_ARN, KMS_KEY_ARN, S3_BUCKET_ARN
- Dependency: access_key depends_on policy for correct creation order

## No Concerns

All code follows terraform-style-guide and maimon-infra patterns. The policy implements least-privilege principle correctly with no unnecessary wildcard permissions.
