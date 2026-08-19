# SDD ledger — plan: docs/superpowers/plans/2026-08-19-align-iam-users.md

## Pre-Flight Scan

| Task Pair | Files | Interface Check | Status |
|---|---|---|---|
| Task 1 → Task 2 | main.tf shared | Task 1 creates skeleton; Task 2 adds resource blocks | ✅ Sequential |
| Task 1 → Task 5 | outputs.tf shared | Task 1 creates; Task 5 adds new outputs | ✅ Sequential |
| Task 2 ↔ Task 3 | Separate policy files | Independent (mosar vs monitoring) | ✅ Can run parallel after Task 1 |
| Task 4 deps | Consumes module.data, module.iam_users | Depends on Tasks 1-3 complete | ✅ Sequential |
| Task 5 deps | Consumes module.iam_users outputs | Depends on Task 1 | ✅ After Task 1 |
| Global constraints | Naming, tagging, permissions scope | Checked in each task | ✅ Clean |

**Execution order:** Task 1 → Task 2 → Task 3 → Task 4 → Task 5 → Task 6

**Plan conflicts:** None found.
**Self-consistency:** All tasks reference consistent variable names, resource naming patterns, and output structures.

---

## Task 1: Create IAM Users Module Skeleton

- [ ] Task 1: complete (commits 8b64774..279dc69, review clean)

**Status:** ✅ COMPLETE
- Created: modules/iam-users/{main.tf, variables.tf, outputs.tf}
- Review verdict: APPROVED
- Code quality: ✅ HCL valid, well-structured, supports Task 2 resource definitions
- Next: Dispatch Task 2

---

## Task 2: Create Mosar Deployment User & Policy

**Status:** ✅ COMPLETE
- Created: modules/iam-users/policies/mosar-deploy.json (6 Sid blocks, all required permissions)
- Modified: modules/iam-users/main.tf (added 3 resources: aws_iam_user, aws_iam_access_key, aws_iam_user_policy)
- Review verdict: APPROVED
- Spec coverage: 100% (all 6 statements, all ARN placeholders, for_each patterns)
- Least-privilege: ✅ No over-permissions, read-only S3/Secrets, decrypt-only KMS
- Commits: 279dc69..bcaeef3
- Next: Task 3 (parallel with Task 2 review if needed)

---

## Task 3: Create Monitoring Deployment User & Policy

**Status:** ✅ COMPLETE
- Created: modules/iam-users/policies/monitoring-deploy.json (4 Sid blocks, no S3/SSM access per spec)
- Review verdict: APPROVED
- Spec coverage: ✅ 4 blocks as specified, correct omissions (S3/SSM not needed for monitoring)
- Least-privilege: ✅ Correctly scoped per service (mosar has S3+SSM, monitoring does not)
- Code quality: ✅ Valid JSON, consistent with mosar pattern, placeholder names correct
- Commits: bcaeef3..58c937d
- Next: Task 4 (module integration into production environment)

---

## Task 4: Wire Up IAM Users Module in Production Environment

**Status:** 🔧 FIX ROUND 1/5

**Initial implementation:** NEEDS_FIXES
- Spec violation: services local uses `keys(var.services)` instead of hardcoded ["mosar", "monitoring"]
- Current services: [monitoring, mosar, notes, kubeman, dmarcer] (all 5 services)
- Expected: [mosar, monitoring] (only deployment services)
- Risk: Runtime failure on terraform apply when accessing secret_arns for undefined services

**Finding (CRITICAL):**
- environments/prod/locals.tf line 28 must change from `services = keys(var.services)` to `services = ["mosar", "monitoring"]`

---

**Fix Round 1 Result:** ✅ APPROVED
- Fix: services local hardcoded to ["mosar", "monitoring"]
- Re-review verdict: ADDRESSED (finding fully resolved)
- No new breakage
- Terraform syntax valid
- Commits: d46bc7f..9058e74

**Status:** ✅ COMPLETE
- All findings resolved after fix round 1
- Module integration now correct and spec-compliant
- Next: Task 5 (add outputs for access key retrieval)

---

## Task 5: Create Outputs for Access Key Retrieval

**Status:** ✅ COMPLETE
- Created: 3 outputs in environments/prod/outputs.tf
  - iam_user_access_keys (sensitive=true)
  - iam_user_access_secrets (sensitive=true)  
  - iam_user_names (not sensitive)
- Review verdict: APPROVED
- Spec coverage: ✅ All outputs present, correct sensitivity markers
- Code quality: ✅ Valid HCL, proper module references, descriptions accurate
- Integration: ✅ Module outputs exist, no circular dependencies
- Terraform validate: ✅ PASS
- Commits: 9058e74..ccb2b80
- Next: Task 6 (documentation)

---

## Task 6: Create Policy Documentation

**Status:** 🔧 FIX ROUND 1/5

**Initial implementation:** NEEDS_FIXES
- Critical: Monitoring policy section incomplete (missing permissions table and scope explanation)
- The docs correctly state monitoring has NO S3 access (unlike mosar)
- But monitoring section lacks detailed breakdown table matching mosar's detail level
- Reviewer findings: asymmetric documentation (mosar fully detailed, monitoring summarized)

**Findings:**
1. CRITICAL: Monitoring section missing detailed Permissions Breakdown table (like Mosar has)
2. IMPORTANT: Monitoring section missing Scope subsection 
3. Documentation currently correct on S3 (monitoring doesn't have it), but needs more detail

---

**Fix Round 1 Result:** ✅ APPROVED
- Permissions Breakdown table added to monitoring section (4 rows)
- Scope subsection added with explicit NO access markers
- Documentation parity achieved with mosar section
- Re-review verdict: ALL FINDINGS ADDRESSED
- No new breakage
- Markdown formatting valid
- Commits: e80690a..95777a5

**Status:** ✅ COMPLETE
- All findings resolved after fix round 1
- Documentation now complete and comprehensive
- Next: FINAL WHOLE-BRANCH REVIEW

---

## PLAN EXECUTION SUMMARY

✅ **All 6 tasks complete:**
- Task 1: Module skeleton ✅
- Task 2: Mosar policy (1 fix round) ✅  
- Task 3: Monitoring policy ✅
- Task 4: Module integration (1 fix round) ✅
- Task 5: IAM outputs ✅
- Task 6: Policy documentation (1 fix round) ✅

**Total commits:** 8b64774..95777a5 (9 commits)
- 279dc69: Task 1 skeleton
- bcaeef3: Task 2 mosar policy
- 58c937d: Task 3 monitoring policy
- d46bc7f: Task 4 integration
- 9058e74: Task 4 fix (services list)
- ccb2b80: Task 5 outputs
- e80690a: Task 6 documentation
- 95777a5: Task 6 fix (monitoring docs)

**Fix rounds:** 2 total (Task 4: 1, Task 6: 1)
**Review verdict so far:** 6/6 tasks approved (after fixes)

---

## FINAL WHOLE-BRANCH REVIEW

**Verdict: BLOCKED** ❌

**Review by:** Opus (most capable model)  
**Scope:** Architecture, implementation quality, least-privilege, integration, documentation, cross-system, risk

---

## CRITICAL FINDINGS (BLOCKS MERGE)

### 1. terraform plan FAILS — Secret ARNs key mismatch
**File:** `modules/iam-users/main.tf:37` and module integration  
**Issue:** 
- Module indexes `var.secret_arns[each.value]` with service name ("mosar", "monitoring")
- But `module.data.secret_arns` is keyed by *logical secret name* ("mosar/runtime", "monitoring/runtime")
- Key shape mismatch causes terraform plan to fail with "Invalid index" error
- Additionally, `mosar/runtime` secret doesn't exist in `environments/prod/local.auto.tfvars:44` (only monitoring/runtime)

**Fix required:** Either:
- Option A: Remap keys in prod integration: `secret_arns = { for s in local.services : s => module.data.secret_arns["${s}/runtime"] }`
- Option B: Update module to accept full logical names

**Impact:** Blocks ALL terraform apply, even unrelated changes

---

## IMPORTANT FINDINGS (NEEDS FIXES)

### 2. Unscoped SSM permissions
**File:** `modules/iam-users/policies/mosar-deploy.json:57-66`  
**Issue:** `ssm:SendCommand` on `"Resource": "*"` permits running any SSM doc on any instance
**Fix:** Scope to instance ARN + specific documents (mirror `modules/deployment/main.tf:84-92`)

### 3. Duplicate OIDC deployment roles
**Issue:** Monitoring already has working OIDC-assumable role in `modules/deployment`; CI already uses it
**Fix:** Justify why static keys are needed, or remove monitoring user

### 4. S3 permissions not service-scoped
**File:** `mosar-deploy.json:45-55`  
**Issue:** Read access to entire shared bucket, not mosar's prefix  
**Fix:** Add object prefix scope or remove (purpose "deployment validation" isn't in code)

### 5. Broken access key rotation procedure
**File:** `docs/IAM_USER_POLICIES.md:60-67`  
**Issues:**
- Step 1: `terraform apply` is no-op; needs `-replace` flag
- Step 3: `delete-access-key` destroys key (not deactivates)
- No zero-downtime support (only 1 key, should use `lifecycle { create_before_destroy = true }`)

### 6. Wrong region in CI example
**File:** `docs/IAM_USER_POLICIES.md:76`  
**Issue:** Shows `il-central-1` but platform uses `eu-central-1`

---

## MINOR FINDINGS (DEFERRED)

- Formatting in environments/prod/main.tf (not fmt-aligned)
- Unused `environment` variable in module
- Redundant `depends_on` statements
- Inconsistent local aliases in prod locals
- Wrong action labels in documentation (pull vs. push)
- AI_STATE.md not updated with new module

---

## NEXT STEPS

Fix Critical + Important findings before final merge.

