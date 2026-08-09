# Cloudflare Tunnel Service Deployment Design

**Date:** 2026-08-10  
**Status:** Design Review  
**Author:** Claude  

## Overview

A GitHub reusable workflow that orchestrates multi-service deployments to a single EC2 instance behind a Cloudflare Tunnel. Each service repo owns its Docker containers and Cloudflare route definitions; the workflow coordinates both deployments.

## Architecture

```
Service Repo (Docker + Terraform)
    ↓
GitHub Reusable Workflow (maimons-infra)
    ├─ Build Docker image
    ├─ Push to ECR
    ├─ SSM → Deploy docker-compose
    ├─ SSM → Terraform apply (Cloudflare routes)
    └─ Health check
    ↓
EC2 Instance
    ├─ cloudflared tunnel (managed by maimons-infra)
    └─ Service containers (localhost:port)
    ↓
Cloudflare (maimons.dev, maimons.org zones)
    └─ Routes point to tunnel
```

**Key Design Decisions:**
- **Single tunnel per account:** One cloudflared daemon on EC2, all services route through it
- **Service ownership:** Each repo owns its Docker config AND Cloudflare route definition
- **Workflow orchestration:** Single reusable workflow handles both Docker and Terraform deployments
- **Blue-green deploy:** Down → Up strategy with rollback on health check failure

## Service Repository Structure

```
service-repo/
├── Dockerfile                    # Build image
├── docker-compose.yml            # Multi-container definition
├── terraform/
│   ├── main.tf                  # Cloudflare app + route definition
│   ├── variables.tf
│   └── terraform.tfvars         # Service-specific values (port, domain, etc.)
├── src/
└── README.md
```

## Workflow Interface

### Inputs

Service repos call the workflow with:

```yaml
uses: maimon33/maimons-infra/.github/workflows/deploy-service.yml@main
with:
  service_name: mosar                          # Container name prefix
  docker_compose_path: ./docker-compose.yml    # Path to compose file
  terraform_path: ./terraform                  # Path to Cloudflare route TF
  port: "3010"                                 # Primary exposed port
  health_check_url: http://localhost:3010/api/health
  health_check_timeout: 30                     # Seconds
```

### Outputs

```yaml
outputs:
  deployment_status: success | failed
  service_url: https://mosar.maimons.org
  health_check_result: passed | timeout | failed
```

## Deployment Flow

### Phase 1: Docker Build & Push
1. Checkout service repo at provided git ref
2. Configure AWS credentials via GitHub OIDC (maimons-infra-github-ssm role)
3. Build Docker image: `docker build -t SERVICE_NAME:SHA .`
4. Push to ECR: `AWS_ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/SERVICE_NAME:SHA`

### Phase 2: Container Deployment (via SSM)
1. Start SSM session to EC2 instance
2. Validate port is free: `netstat -tuln | grep :PORT` (abort if bound)
3. Clone/pull service repo to `/opt/services/SERVICE_NAME`
4. Set environment variable: `IMAGE_TAG=SHA`
5. Execute blue-green deploy:
   - `docker-compose down` (stop old version)
   - `docker-compose up -d` (start new version)
6. Poll health check URL (HTTP GET) until success or timeout
7. If timeout: attempt rollback (see Rollback section)

### Phase 3: Terraform Deployment (Cloudflare Routes)
1. `cd /opt/services/SERVICE_NAME/terraform`
2. `terraform init`
3. `terraform apply -auto-approve`
4. This creates/updates the Cloudflare app and route (service:port → tunnel)

### Phase 4: Validation
- Health check success → workflow succeeds, service live
- Health check timeout → rollback triggered
- Terraform fail → Docker deployed, route not updated, ops alerted

## Multi-Container Services

Services define all containers in `docker-compose.yml`:

```yaml
version: '3'
services:
  web:
    image: mosar:${IMAGE_TAG}
    ports:
      - "3010:3010"
    networks:
      - internal
  worker:
    image: mosar:${IMAGE_TAG}
    networks:
      - internal
    depends_on:
      - web
  redis:
    image: redis:latest
    networks:
      - internal

networks:
  internal:
    driver: bridge
```

**Workflow behavior:**
- Treats entire compose stack as single deployment unit
- Validates only exposed ports (primary service port)
- Health check validates primary service; secondary services implicitly validated by compose success
- All containers start/stop together

## Rollback Strategy

Keep last 3 image versions on EC2, tagged by SHA:

**File:** `/opt/services/SERVICE_NAME/.versions`
```
sha-abc123
sha-def456
sha-ghi789
```

**On health check timeout:**
1. Retrieve previous SHA from `.versions`
2. Update `IMAGE_TAG` environment variable
3. `docker-compose down && docker-compose up -d`
4. Re-run health check
5. If still fails: alert ops, require manual intervention

**Image cleanup:** On successful deploy, add new SHA to `.versions`, keep only latest 3.

## Volume & Data Persistence

Service repos define volumes in `docker-compose.yml`. Workflow behavior:

- **First deploy:** `docker-compose up` creates volumes automatically
- **Redeploy:** Existing volumes preserved, only containers recreated
- **Initialization:** If service needs DB migrations or initial data, define in Dockerfile or include initialization script in service repo (workflow doesn't run custom init)

Example `docker-compose.yml` with persistent volume:
```yaml
services:
  app:
    image: mosar:${IMAGE_TAG}
    volumes:
      - app-data:/app/data

volumes:
  app-data:
    driver: local
```

## Cloudflare Route Management

Service repo's `terraform/main.tf` defines Cloudflare route:

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
  }
}

variable "cloudflare_zone_id" {
  type = string
}

variable "service_port" {
  type = string
}

variable "tunnel_id" {
  type = string
}

resource "cloudflare_tunnel_config" "service" {
  account_id = var.cloudflare_account_id
  tunnel_id  = var.tunnel_id

  config {
    ingress_rule {
      hostname = "mosar.maimons.org"
      service  = "http://localhost:${var.service_port}"
    }
  }
}
```

Service repo provides `terraform.tfvars`:
```hcl
cloudflare_zone_id = "92a1c8a20c71677cd317fdb47533b46d"
service_port = "3010"
tunnel_id = "..." # from maimons-infra
```

**Workflow behavior:** Runs `terraform apply` to create/update route. If apply fails, Docker remains deployed but route not updated — ops alerted.

## Tunnel Infrastructure (maimons-infra)

maimons-infra Terraform manages:

1. **Cloudflare Tunnel Creation**
   - `cloudflare_tunnel` resource
   - `cloudflare_tunnel_virtual_network` (if needed)

2. **Tunnel Credentials**
   - Tunnel token stored in AWS Secrets Manager
   - EC2 instance retrieves token at startup

3. **EC2 Startup Script**
   - Install `cloudflared` binary
   - Start tunnel: `cloudflared tunnel run --token=<TOKEN>`
   - Ensure tunnel persists across reboots (systemd service or similar)

4. **Output:** Tunnel ID stored as Terraform output, made available to service repos via:
   - GitHub repository secret (manual copy after maimons-infra deploy), OR
   - Terraform remote state (service repos read it as data source)

## Error Handling

| Failure | Trigger | Action |
|---------|---------|--------|
| Port in use | Pre-deploy validation | Abort, report which service owns port |
| Docker image not in ECR | Pull phase | Abort, check ECR push step |
| docker-compose syntax error | Up phase | Abort, show compose error output |
| Service health check timeout | Post-deploy validation | Attempt rollback to previous image |
| Rollback health check timeout | Rollback validation | Alert ops, manual intervention required |
| Terraform apply fails | Route phase | Docker deployed but route not updated, alert ops |
| SSM session timeout | Any phase | Retry once, then fail with clear error |

**No silent failures:** Workflow halts at first error with clear messaging.

## Security Considerations

- **GitHub OIDC:** Workflow uses maimons-infra-github-ssm role (OIDC trust scoped to maimon33 org)
- **SSM audit trail:** All commands logged to CloudWatch Logs
- **Port whitelist:** Restrict deployable ports to 3000-4999 (prevents conflicts, system port protection)
- **Cloudflare credentials:** Via GitHub repository secrets, rotated periodically
- **ECR pull:** Services pull images from private ECR (authenticated via IAM role)
- **docker-compose validation:** Reject arbitrary overrides; only allow specific top-level keys (services, networks, volumes)

## Testing Strategy

1. **Workflow syntax:** `yamllint` on workflow file
2. **Integration test:** Deploy test service to staging instance (separate EC2 instance for pre-prod)
3. **Health check validation:** Workflow must validate endpoint returns 2xx before marking success
4. **Rollback test:** Manually trigger health check timeout, verify rollback works
5. **Port conflict test:** Attempt to deploy two services to same port, verify abort

## Assumptions & Constraints

- EC2 instance has Docker, docker-compose, terraform, curl, netstat pre-installed
- cloudflared is running and tunnel is active
- Service repos follow the structure defined in this spec
- Terraform state for Cloudflare routes lives in service repos (not centralized)
- Health check endpoint exists and returns 2xx on success
- All services must be accessible on localhost:port from the EC2 instance

## Out of Scope (Phase 2)

- Canary deployments
- Service mesh / load balancing across multiple instances
- Secrets management (services provide via environment in docker-compose.yml)
- Monitoring/alerting integration (ops alerted manually via workflow output)
- Auto-scaling
- Custom initialization scripts
