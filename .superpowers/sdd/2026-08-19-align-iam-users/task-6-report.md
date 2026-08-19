# Task 6 Report: Create Policy Documentation

**Date:** 2026-08-20  
**Task Type:** Documentation (no code changes)  
**Status:** COMPLETED

## Summary
Created `docs/IAM_USER_POLICIES.md` — a comprehensive policy reference guide for IAM deployment users.

## Deliverables

### File Created
- **Path:** `/Users/assi/Work/repos/maimon33/maimons-infra/docs/IAM_USER_POLICIES.md`
- **Size:** 64 insertions
- **Status:** ✅ Created and verified

### Content Coverage
The documentation includes all required sections:

1. **Overview** — Explains the IAM user pattern for CI/CD credentials
2. **Mosar Deployment User Policy**
   - User name template
   - Permissions breakdown table (6 permissions):
     - ECR push operations
     - ECR authentication token
     - Secrets Manager read
     - KMS decrypt
     - S3 backup read
     - SSM command execution
   - Scope explanations per AWS service
   - "Why minimal" section listing excluded permissions

3. **Monitoring Deployment User Policy**
   - Identical structure to mosar, scoped to monitoring service
   - Clear note: S3 backup access NOT included (not needed)

4. **Access Key Rotation**
   - Storage location (GitHub Secrets)
   - Rotation policy (90-day manual)
   - Step-by-step rotation procedure

5. **Usage in CI/CD**
   - Example GitHub Actions environment variables
   - Shows credential injection pattern

## Verification

- ✅ File created successfully
- ✅ All 9 sections present and properly formatted
- ✅ Markdown formatting validated (tables, code blocks, emojis)
- ✅ Content matches task brief exactly (verbatim)

## Git Commit

```
commit e80690a
Author: Claude Code
Date:   2026-08-20

    docs: add iam user policy reference guide
    
    - Create docs/IAM_USER_POLICIES.md with policy reference
    - Include Mosar and Monitoring user breakdowns
    - Document access key rotation procedures
    - Add CI/CD usage examples
```

## Links

- **Plan File:** `/Users/assi/Work/repos/maimon33/maimons-infra/docs/superpowers/plans/2026-08-19-align-iam-users.md` (Task 6: lines 439–523)
- **Documentation:** `/Users/assi/Work/repos/maimon33/maimons-infra/docs/IAM_USER_POLICIES.md`

## Task Completion

All implementation tasks (1-6) are now complete:
- Tasks 1-5: Terraform module code + integration
- Task 6: Documentation (this task)

Project is ready for review and deployment.

---

## Enhancement: Monitoring Policy Documentation (2026-08-20)

**Update:** Enhanced monitoring section to match mosar's level of detail.

### Changes Made

1. **Added Permissions Breakdown Table** (lines 39-46)
   - ECR push operations (6 actions)
   - ECR authentication token
   - Secrets Manager read (monitoring-specific path)
   - KMS decrypt operations
   - Clearly scoped to monitoring resources only

2. **Added Scope Subsection** (lines 48-53)
   - ECR: Write-only to monitoring repository
   - Secrets: Read-only to `/platform/prod/monitoring/runtime`
   - KMS: Decrypt operations only
   - S3: Explicitly NO access
   - SSM: Explicitly NO access

3. **Enhanced Difference from Mosar Section** (lines 55-58)
   - Clear rationale for excluded S3 access
   - Clear rationale for excluded SSM access
   - Bullet points explaining business logic

### Verification

- ✅ Monitoring section now matches mosar's documentation depth
- ✅ Explicit NO access items (S3, SSM) clearly documented
- ✅ Markdown formatting validated
- ✅ All resource ARNs and paths monitoring-specific

### Git Commit

```
commit 95777a5
Author: Claude Code
Date:   2026-08-20

    fix: enhance monitoring policy documentation with detailed breakdown and scope
    
    - Add Permissions Breakdown table for monitoring policy (4 actions: ECR, Secrets, KMS)
    - Add Scope subsection clearly delineating access boundaries
    - Explicitly document NO S3 and NO SSM access for monitoring deployment
    - Enhance Difference from Mosar section with rationale for excluded permissions
```

---

## Task 6 (follow-up) — Final whole-branch review fixes

Addressed the Critical + Important findings that blocked the branch.

### Critical #1 — Secret ARN key mismatch (terraform plan failure)

`modules/iam-users/main.tf:37` reads `var.secret_arns[each.value]` keyed by service name
(`mosar`, `monitoring`), but `module.data.secret_arns` is keyed by logical secret name
(`mosar/runtime`, `monitoring/runtime`).

- `environments/prod/main.tf` — remapped keys at the module call:
  `secret_arns = { for s in local.services : s => module.data.secret_arns["${s}/runtime"] }`
- `environments/prod/local.auto.tfvars` — `mosar/runtime` was missing from
  `service_secret_names`; added it (only `monitoring/runtime` was present).

Verified: `terraform plan` in `environments/prod/` completes with
`Plan: 54 to add, 6 to change, 0 to destroy` and **zero** `Invalid index` / `Error:` lines.
`module.data.aws_secretsmanager_secret.service["mosar/runtime"]` now appears in the plan.

### Important #2 — Unscoped SSM permissions

`modules/iam-users/policies/mosar-deploy.json` — split the single wildcard
`SSMCommandExecution` statement into two, mirroring the existing pattern in
`modules/deployment/main.tf:84-102`:

- `SSMSendCommand` — `ssm:SendCommand` scoped to
  `arn:aws:ec2:*:*:instance/i-*` and `arn:aws:ssm:*::document/AWS-RunShellScript`
- `SSMCommandStatus` — `GetCommandInvocation` / `ListCommandInvocations` / `CancelCommand`
  remain `"*"`, because command-invocation ARNs are generated at send time and are not
  knowable in a static policy. Scoping these to the instance ARN would break status polling.

### Important #4 — S3 not service-scoped

`modules/iam-users/policies/mosar-deploy.json` — Option A applied. Object resource narrowed
from `${S3_BUCKET_ARN}/*` to `${S3_BUCKET_ARN}/mosar/*`.

Caveat worth surfacing: the bucket-level ARN is retained because `s3:ListBucket` requires it,
so listing is still bucket-wide. A `s3:prefix` condition would be needed to also constrain
listing; object reads are correctly limited to `mosar/`.

### Important #5 — Broken access key rotation procedure

- `modules/iam-users/main.tf` — added `lifecycle { create_before_destroy = true }` to
  `aws_iam_access_key.service_key` so the replacement key exists before the old one is
  destroyed (zero-downtime rotation).
- `docs/IAM_USER_POLICIES.md` — rewrote the rotation steps:
  - step 1 now uses
    `terraform apply -replace='module.iam_users.aws_iam_access_key.service_key["mosar"]'`
    and explains why a plain `terraform apply` is a no-op
  - documents the `create_before_destroy` behaviour
  - step 3 corrected: `aws iam update-access-key --status Inactive` to deactivate,
    `aws iam delete-access-key` called out as permanent deletion

### Important #6 — Wrong region in CI example

`docs/IAM_USER_POLICIES.md` — `AWS_REGION: il-central-1` → `eu-central-1`, matching
`backend.hcl` and `local.auto.tfvars`.

Also refreshed the mosar permissions table and Scope bullets so the docs match the tightened
S3 prefix and split SSM statements.

### Verification

- `terraform validate` → `Success! The configuration is valid.`
- `terraform plan` (prod) → succeeds, no `Invalid index`, no errors
- `mosar-deploy.json` parses as valid JSON; 7 statements:
  ECRPushAccess, ECRAuthToken, SecretsManagerRead, KMSDecrypt, S3BackupRead,
  SSMSendCommand, SSMCommandStatus
- `terraform fmt -check -recursive` reports the same pre-existing unformatted files as before
  these edits (no new formatting regressions introduced)
