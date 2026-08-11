# AI_STATE.md

Shared context for AI tools working on this project.

## Project Purpose & Stack

**Purpose:** Shared infrastructure hosting multiple applications behind a Cloudflare Tunnel with Zero Trust access control, deployed on EC2 with Infrastructure as Code.

**Stack:**
- **IaC:** Terraform (AWS + Cloudflare)
- **Compute:** EC2 (t3.large, eu-central-1)
- **Container:** Docker Compose
- **Networking:** Cloudflare Tunnel + DNS + Zero Trust Access
- **CI/CD:** GitHub Actions with OIDC role assumption
- **Secrets:** AWS Secrets Manager (KMS-encrypted)
- **Monitoring:** CloudWatch alarms + custom dashboard

## Key File Map

| Path | Purpose |
|------|---------|
| `environments/prod/` | Canonical production Terraform root |
| `environments/prod/local.auto.tfvars` | Service definitions (hostname, port, access control) |
| `modules/cloudflare-tunnel/` | Cloudflare Tunnel & ingress rules |
| `modules/identity/` | GitHub OIDC provider + IAM roles |
| `platform/compose.yaml` | Docker services on EC2 |
| `.github/workflows/deploy-monitoring.yml` | Monitoring app deployment |
| `ADDING_SERVICES.md` | Guide for adding new apps |

## Active Conventions

### Service Definition
Services are defined in `local.auto.tfvars` under the `services` map. Each service creates:
- Cloudflare DNS CNAME record (proxied through edge)
- Cloudflare Zero Trust Access application (email-based auth)
- Tunnel ingress rule (hostname → http://127.0.0.1:port)

### Port Assignment
- Ports 3000-3999 are reserved for applications
- Port 20241 reserved for tunnel metrics
- All apps bind to 127.0.0.1 (localhost only, Cloudflare accesses via tunnel)

### Terraform State
- State stored in S3 with versioning + encryption
- State locking via DynamoDB
- Local backend file: `environments/prod/terraform.tfstate`
- NEVER commit state files to git

### GitHub Actions OIDC
- GitHub OIDC provider thumbprint: `227203b5317f3818cab5b5ce596132bf36748c0e`
- Trust policy requires subject: `repo:maimon33/maimons-infra:*`
- Workflow audience: `sts.amazonaws.com`
- Role: `maimons-infra-github-ssm` for deployment

### Cloudflare Configuration
- Zones: maimons.dev (6f74b16f5d9fbaa7ec6c57253dc321e8) + maimons.org (92a1c8a20c71677cd317fdb47533b46d)
- Tunnel: cloudflared on EC2 running as systemd service
- Tunnel config: `/etc/cloudflared/config.yml` (local file, remote API config as fallback)
- Session duration: 720 hours (30 days) for Cloudflare Access
- DNS records must be "proxied" (orange cloud) to route through Cloudflare edge

### Deployment Pattern
1. Push to main → GitHub Actions triggers
2. Action assumes OIDC role → uploads image to ECR
3. Action runs SSM command on EC2 → Docker pull & restart
4. Health checks verify deployment → rollback on failure

## Current Status

**Working:**
- ✅ Cloudflare Tunnel routing (monitoring.maimons.dev + mosar.maimons.org)
- ✅ Cloudflare Zero Trust Access (email-based auth)
- ✅ GitHub OIDC role assumption (fixed thumbprint issue)
- ✅ Docker Compose deployments on EC2
- ✅ Terraform state management

**Recent Fixes:**
- Fixed GitHub OIDC provider thumbprint (was missing from Terraform, causing invalid cert validation)
- Updated workflow to explicitly set audience parameter
- Cloudflare module now receives api_token for proper authentication
- Session duration set to 720h (30 days) for monitoring app

**Known Issues:**
- Terraform state lock sometimes sticks (use `-lock=false` for manual runs, only SSM/GitHub Actions should touch state)
- Cloudflare DNS records occasionally show as proxied=false after Terraform apply (update manually in CF dashboard if needed)

## Relevant Decisions

1. **Centralized service configuration** - All ingress rules and routing defined in maimons-infra Terraform, not distributed across repos. Keeps infrastructure as single source of truth.

2. **Local cloudflared config fallback** - Tunnel ingress rules defined in both Terraform API + local `/etc/cloudflared/config.yml` to survive remote API outages.

3. **Localhost-only binding** - Apps only accessible via Cloudflare tunnel (127.0.0.1), never exposed directly. Security group only allows Cloudflare IPs.

4. **Session-based access** - Cloudflare Access provides auth layer, no app-level auth required for simple services.

## Session Log

### 2026-08-12 — Fixed GitHub OIDC role assumption for deployments
- **Problem:** GitHub Actions workflow couldn't assume IAM role despite correct trust policy configuration
- **Root cause:** OIDC provider had invalid thumbprint (all F's) instead of GitHub's actual certificate thumbprint
- **Solution:** 
  - Added correct thumbprint `227203b5317f3818cab5b5ce596132bf36748c0e` to Terraform code
  - Updated workflow to explicitly set `audience: sts.amazonaws.com`
  - Modified trust policy to use `job_workflow_ref` condition for flexibility
  - Recreated OIDC provider with correct config
- **Outcome:** Workflow should now successfully assume role and deploy services
- **Follow-up:** Test deployment workflow on next push to main

### 2026-08-11 — Added Cloudflare Access and session configuration
- **Change:** Updated monitoring app to require email authentication + extended session to 30 days
- **Files:** `environments/prod/cloudflare-access.tf`, `modules/cloudflare-tunnel/main.tf`
- **Status:** Waiting for Terraform apply (stuck on pre-existing resources, not blocking)

### 2026-08-09 — Initial deployment of complete infrastructure
- **Completed:** EC2 instance + Cloudflare Tunnel + monitoring + mosar services
- **Services:** monitoring.maimons.dev (port 3000) + mosar.maimons.org (port 3001)
- **Status:** Infrastructure working, services accessible with Cloudflare Access auth
