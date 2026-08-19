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
| `s3:GetObject`, `s3:ListBucket` | Backup bucket + `mosar/*` objects | Retrieve backup data for deployment validation |
| `ssm:SendCommand` | `arn:aws:ec2:*:*:instance/i-*` + `AWS-RunShellScript` document | Execute deployment commands on EC2 instances |
| `ssm:GetCommandInvocation`, `ssm:ListCommandInvocations`, `ssm:CancelCommand` | `*` | Track and cancel in-flight command invocations |

### Scope
- **ECR**: Write access limited to mosar's repository ARN only (no cross-service access)
- **Secrets**: Read-only access to `/platform/prod/mosar/runtime` secret
- **KMS**: Decrypt operations only (no key management permissions)
- **S3**: Read-only access to the `mosar/` prefix of the backup bucket (no delete/put permissions)
- **SSM**: `SendCommand` scoped to EC2 instances and the `AWS-RunShellScript` document; status operations only

### Why This Policy is Minimal
- ❌ No S3 `PutObject`, `DeleteObject`, `PutBucketPolicy` (read-only backup access)
- ❌ No ECR `DeleteRepository`, `PutRepositoryPolicy` (image push only)
- ❌ No `secretsmanager:CreateSecret`, `UpdateSecret`, `DeleteSecret` (read-only)
- ❌ No KMS `CreateGrant`, `ScheduleKeyDeletion`, `DisableKey` (decrypt-only)
- ❌ No IAM, CloudFormation, or account-level permissions

## Monitoring Deployment User Policy

**User Name:** `{name_prefix}-monitoring-deploy-user`

### Permissions Breakdown

| Action | Resource | Purpose |
|--------|----------|---------|
| `ecr:PutImage`, `ecr:CompleteLayerUpload`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer`, `ecr:BatchGetImage` | Monitoring ECR repository ARN | Push Docker images during CI/CD builds |
| `ecr:GetAuthorizationToken` | `*` | Authenticate with ECR registry |
| `secretsmanager:GetSecretValue`, `secretsmanager:DescribeSecret` | `/platform/prod/monitoring/runtime` secret ARN | Retrieve runtime configuration secrets |
| `kms:Decrypt`, `kms:DescribeKey` | Platform KMS key ARN | Decrypt secrets encrypted at rest |

### Scope
- **ECR**: Write access limited to monitoring's repository ARN only (no cross-service access)
- **Secrets**: Read-only access to `/platform/prod/monitoring/runtime` secret
- **KMS**: Decrypt operations only (no key management permissions)
- **S3**: NO access (monitoring deployment does not require backup bucket access)
- **SSM**: NO access (monitoring deployment does not require instance command execution)

### Difference from Mosar
Monitoring policy intentionally excludes S3 and SSM permissions that mosar requires:
- **No S3 access**: Monitoring does not perform backup validation or data retrieval
- **No SSM access**: Monitoring deployment does not require EC2 instance command execution

## Access Key Rotation

- Access keys stored securely in GitHub Secrets (one per service)
- Rotation policy: 90-day manual rotation (update key, rotate secret in GitHub, deactivate old key)
- The `aws_iam_access_key` resource uses `create_before_destroy = true`, so the replacement key is created and usable before the old one is removed (zero-downtime rotation).
- To rotate:
  1. Force a new access key. A plain `terraform apply` is a no-op because nothing in the resource changed, so target the resource for replacement:
     ```bash
     terraform apply -replace='module.iam_users.aws_iam_access_key.service_key["mosar"]'
     ```
  2. Update GitHub Secrets with the new credentials and confirm a deploy succeeds with them.
  3. Retire the old key. Note that `delete-access-key` **deletes** the key; use `update-access-key` to deactivate while keeping it recoverable:
     ```bash
     # Deactivate (not delete) the old key - keeps it available for the 90-day recovery window
     aws iam update-access-key --access-key-id <old-key-id> --status Inactive

     # Or permanently delete once the new key is confirmed working
     aws iam delete-access-key --access-key-id <old-key-id>
     ```

## Usage in CI/CD

Export credentials as environment variables in GitHub Actions:
```yaml
env:
  AWS_ACCESS_KEY_ID: ${{ secrets.MOSAR_AWS_ACCESS_KEY_ID }}
  AWS_SECRET_ACCESS_KEY: ${{ secrets.MOSAR_AWS_SECRET_ACCESS_KEY }}
  AWS_REGION: eu-central-1
```
