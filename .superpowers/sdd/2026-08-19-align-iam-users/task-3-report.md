# Task 3 Status Report: Create Monitoring Deployment User & Policy

**Date:** 2026-08-20  
**Task:** Create monitoring deployment IAM policy (monitoring-deploy.json)  
**Status:** ✅ DONE

---

## Summary

Successfully created `modules/iam-users/policies/monitoring-deploy.json` with a 4-statement least-privilege IAM policy for the monitoring service deployment user.

---

## Changes Made

### File Created
- **Path:** `modules/iam-users/policies/monitoring-deploy.json`
- **Lines:** 45 insertions
- **Format:** JSON (validated)

### Policy Structure

The monitoring policy includes 4 statement blocks (distinct from mosar which includes 6):

| Sid | Actions | Resource | Purpose |
|-----|---------|----------|---------|
| ECRPushAccess | 7 ECR push/layer actions | `${ECR_REPO_ARN}` (monitoring only) | Push Docker images during CI/CD builds |
| ECRAuthToken | `ecr:GetAuthorizationToken` | `*` | Authenticate with ECR registry |
| SecretsManagerRead | `GetSecretValue`, `DescribeSecret` | `${SECRET_ARN}` (monitoring only) | Retrieve monitoring runtime secrets |
| KMSDecrypt | `Decrypt`, `DescribeKey` | `${KMS_KEY_ARN}` | Decrypt secrets encrypted at rest |

### Key Design Decisions

1. **No S3 Backup Access**: Unlike mosar, monitoring does not require S3 backup read permissions (monitoring doesn't need backup access for deployments)
2. **No SSM Permissions**: Unlike mosar, monitoring does not include SSM command execution permissions
3. **Service-Scoped Resources**: All ECR and Secrets Manager resources scoped to monitoring service only via template variables
4. **Template Variables Retained**: `${ECR_REPO_ARN}`, `${SECRET_ARN}`, `${KMS_KEY_ARN}` remain as template variables for Terraform `templatefile()` processing in main.tf

---

## Validation & Testing

✅ **JSON Validation:** Passed using Python `json.tool` module  
✅ **Commit:** Successfully created with commit SHA `58c937d`  
✅ **Git Status:** File tracked and committed to `main` branch  

---

## Commit Details

```
Commit: 58c937d
Message: feat: create monitoring deployment user with least-privilege policy

Creates monitoring-deploy.json IAM policy with 4 least-privilege statement blocks:
- ECRPushAccess: Push Docker images to monitoring ECR repository
- ECRAuthToken: Authenticate with ECR registry
- SecretsManagerRead: Retrieve monitoring runtime secrets
- KMSDecrypt: Decrypt secrets encrypted at rest

Scoped to monitoring service resources only (no S3 backup access required).
```

---

## Integration Status

- ✅ Policy file created and committed
- ✅ Follows existing mosar policy format/structure
- ✅ Compatible with `aws_iam_user_policy` resource using `templatefile()` (as defined in main.tf)
- ✅ Ready for Task 4: Module integration into `environments/prod/main.tf`

---

## Notes

- Policy is independent and does not modify existing main.tf (Task 2 already defines the for_each pattern)
- Monitoring service scoping handled at policy ARN level using template variables
- This task is isolated from Task 2 per project plan specifications
