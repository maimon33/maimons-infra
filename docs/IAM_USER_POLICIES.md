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
