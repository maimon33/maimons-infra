# Cloudflare Tunnel Service Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable GitHub workflow that orchestrates multi-service deployments to EC2 behind a Cloudflare Tunnel, with infrastructure for tunnel management in maimons-infra.

**Architecture:** Single Cloudflare Tunnel per account routes traffic from multiple zones (maimons.dev, maimons.org) to services running on localhost:port. Each service repo owns Docker config + Cloudflare route Terraform. Deployment workflow handles build → push → SSM deploy → health check → Terraform apply.

**Tech Stack:** Cloudflare Tunnels, GitHub Actions (reusable workflow), Terraform (tunnel + routes), Docker Compose, AWS SSM, EC2

## Global Constraints

- **One tunnel per account** — serves all zones and all services; no multi-tunnel logic
- **Single EC2 instance** — all services run on same instance, different ports
- **Port range:** 3000-4999 (system port protection)
- **SSM access:** Via GitHub OIDC role (maimons-infra-github-ssm)
- **Docker:** Multi-container support (docker-compose.yml with networks, volumes)
- **Deploy strategy:** Blue-green (down → up) with rollback on health check failure
- **Terraform syntax:** Follow existing patterns in maimons-infra (modules, local tags, etc.)
- **AWS Region:** eu-central-1
- **Cloudflare Account ID:** c87c068911c8932fbedbf38dae693466

---

## Task 1: Create Cloudflare Tunnel Terraform Module

**Files:**
- Create: `modules/cloudflare-tunnel/main.tf`
- Create: `modules/cloudflare-tunnel/variables.tf`
- Create: `modules/cloudflare-tunnel/outputs.tf`

**Interfaces:**
- Consumes: `var.cloudflare_account_id`, `var.cloudflare_api_token`, `var.aws_region`, `var.aws_secrets_manager_kms_key_arn`, `var.tags`
- Produces: `output.tunnel_id`, `output.tunnel_token_secret_arn`, `output.tunnel_cname`

**Steps:**

- [ ] **Step 1: Create `modules/cloudflare-tunnel/variables.tf`**

```hcl
variable "cloudflare_account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Tunnel permissions."
  type        = string
  sensitive   = true
}

variable "tunnel_name" {
  description = "Name of the Cloudflare Tunnel."
  type        = string
  default     = "maimons-platform"
}

variable "aws_region" {
  description = "AWS region for storing tunnel credentials."
  type        = string
}

variable "aws_secrets_manager_kms_key_arn" {
  description = "KMS key ARN for encrypting secrets in Secrets Manager."
  type        = string
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Create `modules/cloudflare-tunnel/main.tf`**

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Create the Cloudflare Tunnel
resource "cloudflare_tunnel" "platform" {
  account_id = var.cloudflare_account_id
  name       = var.tunnel_name
  secret     = random_password.tunnel_secret.result
}

# Generate a random secret for the tunnel
resource "random_password" "tunnel_secret" {
  length  = 32
  special = true
}

# Get tunnel token
resource "cloudflare_tunnel_token" "platform" {
  account_id = var.cloudflare_account_id
  tunnel_id  = cloudflare_tunnel.platform.id
}

# Store tunnel token in AWS Secrets Manager
resource "aws_secretsmanager_secret" "tunnel_token" {
  name                    = "maimons/cloudflare-tunnel-token"
  kms_key_id              = var.aws_secrets_manager_kms_key_arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tunnel_token" {
  secret_id     = aws_secretsmanager_secret.tunnel_token.id
  secret_string = cloudflare_tunnel_token.platform.token
}

# Store tunnel credentials for manual reference
resource "aws_secretsmanager_secret" "tunnel_config" {
  name                    = "maimons/cloudflare-tunnel-config"
  kms_key_id              = var.aws_secrets_manager_kms_key_arn
  recovery_window_in_days = 7

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "tunnel_config" {
  secret_id = aws_secretsmanager_secret.tunnel_config.id
  secret_string = jsonencode({
    tunnel_id   = cloudflare_tunnel.platform.id
    account_id  = var.cloudflare_account_id
    tunnel_name = cloudflare_tunnel.platform.name
  })
}
```

- [ ] **Step 3: Create `modules/cloudflare-tunnel/outputs.tf`**

```hcl
output "tunnel_id" {
  description = "Cloudflare Tunnel ID."
  value       = cloudflare_tunnel.platform.id
}

output "tunnel_cname" {
  description = "CNAME record for tunnel (for manual DNS setup)."
  value       = cloudflare_tunnel.platform.cname
}

output "tunnel_token_secret_arn" {
  description = "ARN of the secret storing the tunnel token in Secrets Manager."
  value       = aws_secretsmanager_secret.tunnel_token.arn
}

output "tunnel_config_secret_arn" {
  description = "ARN of the secret storing tunnel configuration."
  value       = aws_secretsmanager_secret.tunnel_config.arn
}
```

- [ ] **Step 4: Validate module syntax**

Run: `terraform -chdir=modules/cloudflare-tunnel init && terraform -chdir=modules/cloudflare-tunnel validate`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add modules/cloudflare-tunnel/
git commit -m "feat: add Cloudflare Tunnel Terraform module

- Creates tunnel and stores token in AWS Secrets Manager
- Outputs tunnel ID for service repo reference
- KMS encryption for stored credentials

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Create EC2 Startup Script for cloudflared

**Files:**
- Create: `modules/ec2-startup/cloudflared-startup.sh`

**Interfaces:**
- Consumes: EC2 instance must have `curl`, `unzip`, `systemctl`, and AWS CLI installed
- Produces: systemd service `cloudflared` running on instance startup

**Steps:**

- [ ] **Step 1: Create `modules/ec2-startup/cloudflared-startup.sh`**

```bash
#!/bin/bash
set -euo pipefail

# Log all output
exec > >(tee -a /var/log/cloudflared-startup.log)
exec 2>&1

echo "[$(date)] Starting cloudflared installation and setup"

# Configuration
AWS_REGION="${AWS_REGION:-eu-central-1}"
SECRETS_MANAGER_SECRET_NAME="${SECRETS_MANAGER_SECRET_NAME:-maimons/cloudflare-tunnel-token}"
CLOUDFLARED_USER="cloudflared"
CLOUDFLARED_HOME="/opt/cloudflared"
CLOUDFLARED_CERT_PATH="${CLOUDFLARED_HOME}/.cloudflared"

# Step 1: Install cloudflared
echo "[$(date)] Installing cloudflared..."
if ! command -v cloudflared &> /dev/null; then
  cd /tmp
  curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.tgz -o cloudflared.tgz
  tar xzf cloudflared.tgz
  sudo install -m 755 cloudflared /usr/local/bin/
  rm -f cloudflared cloudflared.tgz
  echo "[$(date)] cloudflared installed"
else
  echo "[$(date)] cloudflared already installed: $(cloudflared --version)"
fi

# Step 2: Create cloudflared system user
echo "[$(date)] Setting up cloudflared user and directories..."
if ! id "${CLOUDFLARED_USER}" &>/dev/null; then
  sudo useradd --system --home-dir "${CLOUDFLARED_HOME}" --shell /usr/sbin/nologin "${CLOUDFLARED_USER}"
fi

sudo mkdir -p "${CLOUDFLARED_CERT_PATH}"
sudo chown -R "${CLOUDFLARED_USER}:${CLOUDFLARED_USER}" "${CLOUDFLARED_HOME}"
sudo chmod 755 "${CLOUDFLARED_HOME}"

# Step 3: Retrieve tunnel token from AWS Secrets Manager
echo "[$(date)] Retrieving tunnel token from Secrets Manager..."
TUNNEL_TOKEN=$(aws secretsmanager get-secret-value \
  --secret-id "${SECRETS_MANAGER_SECRET_NAME}" \
  --region "${AWS_REGION}" \
  --query SecretString \
  --output text)

if [ -z "${TUNNEL_TOKEN}" ]; then
  echo "[$(date)] ERROR: Failed to retrieve tunnel token from Secrets Manager"
  exit 1
fi

# Step 4: Create cloudflared config directory and credentials
echo "[$(date)] Configuring cloudflared..."
cat > "${CLOUDFLARED_CERT_PATH}/credentials.json" << EOF
${TUNNEL_TOKEN}
EOF

sudo chown "${CLOUDFLARED_USER}:${CLOUDFLARED_USER}" "${CLOUDFLARED_CERT_PATH}/credentials.json"
sudo chmod 600 "${CLOUDFLARED_CERT_PATH}/credentials.json"

# Step 5: Create systemd service file
echo "[$(date)] Creating systemd service..."
sudo tee /etc/systemd/system/cloudflared.service > /dev/null << EOF
[Unit]
Description=Cloudflare Tunnel Service
After=network.target
StartLimitInterval=0

[Service]
Type=simple
User=${CLOUDFLARED_USER}
WorkingDirectory=${CLOUDFLARED_HOME}
ExecStart=/usr/local/bin/cloudflared tunnel run --credentials-file=${CLOUDFLARED_CERT_PATH}/credentials.json
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Step 6: Enable and start the service
echo "[$(date)] Enabling and starting cloudflared service..."
sudo systemctl daemon-reload
sudo systemctl enable cloudflared
sudo systemctl start cloudflared

# Verify service is running
sleep 5
if sudo systemctl is-active --quiet cloudflared; then
  echo "[$(date)] SUCCESS: cloudflared service is running"
else
  echo "[$(date)] WARNING: cloudflared service failed to start. Check logs:"
  sudo systemctl status cloudflared || true
  exit 1
fi

echo "[$(date)] cloudflared setup complete"
```

- [ ] **Step 2: Verify script syntax**

Run: `bash -n modules/ec2-startup/cloudflared-startup.sh`

Expected: No syntax errors

- [ ] **Step 3: Make script executable**

Run: `chmod +x modules/ec2-startup/cloudflared-startup.sh`

- [ ] **Step 4: Commit**

```bash
git add modules/ec2-startup/cloudflared-startup.sh
git commit -m "feat: add EC2 startup script for cloudflared

- Installs cloudflared daemon
- Retrieves tunnel token from AWS Secrets Manager
- Creates systemd service for automatic startup
- Logs all operations to /var/log/cloudflared-startup.log

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Wire Tunnel Module into Production Environment

**Files:**
- Modify: `environments/prod/main.tf`
- Create: `environments/prod/cloudflare-tunnel.tf`
- Modify: `environments/prod/outputs.tf`
- Modify: `environments/prod/variables.tf`

**Interfaces:**
- Consumes: `var.cloudflare_account_id`, `var.cloudflare_api_token` (from terraform.tfvars)
- Produces: `output.cloudflare_tunnel_id`, `output.cloudflare_tunnel_token_secret_arn`

**Steps:**

- [ ] **Step 1: Add variables to `environments/prod/variables.tf`**

```hcl
variable "cloudflare_account_id" {
  description = "Cloudflare account ID for tunnel creation."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token for tunnel management."
  type        = string
  sensitive   = true
}
```

- [ ] **Step 2: Create `environments/prod/cloudflare-tunnel.tf`**

```hcl
module "cloudflare_tunnel" {
  source = "../../modules/cloudflare-tunnel"

  cloudflare_account_id          = var.cloudflare_account_id
  cloudflare_api_token           = var.cloudflare_api_token
  aws_region                     = var.aws_region
  aws_secrets_manager_kms_key_arn = module.data.kms_key_arn
  tags                           = local.common_tags
}
```

- [ ] **Step 3: Add outputs to `environments/prod/outputs.tf`**

```hcl
output "cloudflare_tunnel_id" {
  description = "Cloudflare Tunnel ID for service routing."
  value       = module.cloudflare_tunnel.tunnel_id
}

output "cloudflare_tunnel_cname" {
  description = "Tunnel CNAME for DNS records."
  value       = module.cloudflare_tunnel.tunnel_cname
}

output "cloudflare_tunnel_token_secret_arn" {
  description = "ARN of AWS Secrets Manager secret storing tunnel token."
  value       = module.cloudflare_tunnel.tunnel_token_secret_arn
}
```

- [ ] **Step 4: Update `environments/prod/terraform.tfvars.example`**

Add these lines:
```hcl
cloudflare_account_id = "c87c068911c8932fbedbf38dae693466"
cloudflare_api_token  = "REPLACE_WITH_CLOUDFLARE_API_TOKEN"
```

- [ ] **Step 5: Validate syntax**

Run: `terraform -chdir=environments/prod validate`

Expected: PASS

- [ ] **Step 6: Plan (don't apply yet)**

Run: `terraform -chdir=environments/prod plan -out=tfplan`

Review output — should show tunnel creation, secret creation.

- [ ] **Step 7: Commit**

```bash
git add environments/prod/cloudflare-tunnel.tf environments/prod/variables.tf environments/prod/outputs.tf environments/prod/terraform.tfvars.example
git commit -m "feat: integrate Cloudflare Tunnel module into prod environment

- Wires up tunnel creation via module
- Exports tunnel ID for service repo use
- Stores token in AWS Secrets Manager

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Create Reusable GitHub Workflow for Service Deployment

**Files:**
- Create: `.github/workflows/deploy-service.yml`

**Interfaces:**
- Consumes (workflow inputs): `service_name`, `docker_compose_path`, `terraform_path`, `port`, `health_check_url`, `health_check_timeout`
- Consumes (secrets): `AWS_ROLE_ARN`, `EC2_INSTANCE_ID`, `CLOUDFLARE_API_TOKEN`
- Produces (outputs): `deployment_status`, `service_url`, `health_check_result`

**Steps:**

See full workflow YAML in original plan document. Create `.github/workflows/deploy-service.yml` with complete workflow implementation including:
- Docker build and push to ECR
- SSM deployment script
- Port validation
- Health check polling
- Rollback on failure
- Terraform apply for Cloudflare routes

After creation:
- Run: `yamllint -d relaxed .github/workflows/deploy-service.yml` (install if needed)
- Expected: No errors
- Commit with message referencing blue-green deploy, health checks, rollback

---

## Task 5: Create Service Repo Template Documentation

**Files:**
- Create: `docs/SERVICE_REPO_TEMPLATE.md`
- Create: `platform/DEPLOYMENT.md`

**Interfaces:**
- Consumes: Nothing (documentation only)
- Produces: Clear examples for service repos to follow

Create both documentation files with:
- Service repo directory structure
- Example Dockerfile
- Example docker-compose.yml with multi-container setup
- Example Terraform for Cloudflare routes
- Example GitHub workflow that calls the reusable workflow
- Deployment guide with troubleshooting

---

## Task 6: End-to-End Validation

**Files:**
- None (validation only)

**Steps:**

- [ ] Validate all Terraform syntax: `terraform fmt -check -recursive modules/ environments/`
- [ ] Validate workflow: `yamllint -d relaxed .github/workflows/deploy-service.yml`
- [ ] Plan infrastructure: `terraform -chdir=environments/prod plan` (review output)
- [ ] Verify documentation: checklist all files present and complete
- [ ] Create KNOWN_LIMITATIONS.md documenting scope boundaries

