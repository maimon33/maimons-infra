# Service Repository Template

This guide explains how to structure a service repository for deployment through the maimons-infra Cloudflare Tunnel and GitHub Actions workflow.

## Directory Structure

Every service repository should follow this structure:

```
service-repo/
├── Dockerfile                    # Docker image build definition
├── docker-compose.yml            # Multi-container orchestration (all services)
├── terraform/
│   ├── main.tf                   # Cloudflare tunnel route definition
│   ├── variables.tf              # Terraform variables
│   └── terraform.tfvars          # Service-specific values (port, domain, tunnel ID)
├── src/                          # Application source code
├── .github/
│   └── workflows/
│       └── deploy.yml            # Calls maimons-infra reusable workflow
├── README.md
└── .gitignore
```

## Docker Configuration

### Example Dockerfile

```dockerfile
FROM node:20-alpine

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY src/ ./src/

# Expose port (primary service port)
EXPOSE 3010

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3010/api/health', (r) => {if (r.statusCode !== 200) throw new Error(r.statusCode)})"

# Start application
CMD ["npm", "start"]
```

**Key Points:**
- Alpine images minimize layer size
- Use specific version tags (not `latest`)
- Define HEALTHCHECK for deployment validation
- Expose the primary service port
- Install only production dependencies in production image

### Example docker-compose.yml

Single container service:

```yaml
version: '3.9'

services:
  mosar:
    image: mosar:${IMAGE_TAG}
    container_name: mosar-service
    ports:
      - "3010:3010"
    environment:
      NODE_ENV: production
      LOG_LEVEL: info
    restart: unless-stopped
    networks:
      - default

networks:
  default:
    driver: bridge
```

Multi-container service with dependencies:

```yaml
version: '3.9'

services:
  api:
    image: mosar:${IMAGE_TAG}
    container_name: mosar-api
    ports:
      - "3010:3010"
    environment:
      NODE_ENV: production
      DATABASE_URL: postgres://mosar:password@db:5432/mosar
      REDIS_URL: redis://cache:6379
    depends_on:
      - db
      - cache
    restart: unless-stopped
    networks:
      - internal

  worker:
    image: mosar:${IMAGE_TAG}
    container_name: mosar-worker
    environment:
      NODE_ENV: production
      DATABASE_URL: postgres://mosar:password@db:5432/mosar
      REDIS_URL: redis://cache:6379
    depends_on:
      - db
      - cache
    restart: unless-stopped
    networks:
      - internal

  db:
    image: postgres:16-alpine
    container_name: mosar-db
    environment:
      POSTGRES_USER: mosar
      POSTGRES_PASSWORD: password
      POSTGRES_DB: mosar
    volumes:
      - db-data:/var/lib/postgresql/data
    restart: unless-stopped
    networks:
      - internal

  cache:
    image: redis:7-alpine
    container_name: mosar-cache
    restart: unless-stopped
    networks:
      - internal

networks:
  internal:
    driver: bridge

volumes:
  db-data:
    driver: local
```

**Key Points:**
- Use `${IMAGE_TAG}` environment variable for the primary service image (set by deployment workflow)
- Define all containers in a single compose file
- Use internal networks to isolate containers
- Define persistent volumes for stateful services
- Set `restart: unless-stopped` for automatic recovery
- List dependencies with `depends_on`

## Terraform Configuration

### Example main.tf (Cloudflare Route)

```hcl
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.22"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# Cloudflare tunnel configuration for this service
resource "cloudflare_tunnel_config" "service" {
  account_id = var.cloudflare_account_id
  tunnel_id  = var.tunnel_id

  config {
    ingress_rule {
      hostname = var.service_hostname
      service  = "http://localhost:${var.service_port}"
    }

    # Catch-all rule (should appear last)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

# DNS record pointing to tunnel
resource "cloudflare_record" "service" {
  zone_id = var.cloudflare_zone_id
  name    = var.service_subdomain
  type    = "CNAME"
  content = var.tunnel_cname
  ttl     = 1  # Auto TTL
}
```

### Example variables.tf

```hcl
variable "cloudflare_api_token" {
  description = "Cloudflare API token for managing routes."
  type        = string
  sensitive   = true
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID (from maimons-infra outputs)."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for DNS record creation."
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare Tunnel ID (from maimons-infra outputs)."
  type        = string
}

variable "tunnel_cname" {
  description = "Cloudflare Tunnel CNAME (from maimons-infra outputs)."
  type        = string
}

variable "service_port" {
  description = "Port where the service listens on localhost."
  type        = string
  # Must be in range 3000-4999
}

variable "service_hostname" {
  description = "Full hostname for the service (e.g., mosar.maimons.org)."
  type        = string
}

variable "service_subdomain" {
  description = "Subdomain for DNS record (e.g., mosar)."
  type        = string
}
```

### Example terraform.tfvars

```hcl
# Retrieve these values from maimons-infra outputs
cloudflare_account_id = "c87c068911c8932fbedbf38dae693466"
tunnel_id             = "YOUR_TUNNEL_ID_FROM_MAIMONS_INFRA"
tunnel_cname          = "YOUR_TUNNEL_CNAME_FROM_MAIMONS_INFRA"

# Zone ID for maimons.org
cloudflare_zone_id = "92a1c8a20c71677cd317fdb47533b46d"

# Service-specific configuration
service_port       = "3010"
service_subdomain  = "mosar"
service_hostname   = "mosar.maimons.org"
```

**Key Points:**
- Reference tunnel ID and CNAME from maimons-infra (either via GitHub secrets or Terraform remote state)
- Define only one ingress rule per service (catch-all rule at the end)
- Use CNAME DNS records pointing to the tunnel CNAME
- Keep service-specific values in terraform.tfvars

## GitHub Workflow

### Example deploy.yml

This workflow calls the reusable workflow in maimons-infra:

```yaml
name: Deploy Service

on:
  push:
    branches:
      - main
    paths:
      - 'src/**'
      - 'Dockerfile'
      - 'docker-compose.yml'
      - '.github/workflows/deploy.yml'
  workflow_dispatch:

jobs:
  deploy:
    uses: maimon33/maimons-infra/.github/workflows/deploy-service.yml@main
    with:
      service_name: mosar
      docker_compose_path: ./docker-compose.yml
      terraform_path: ./terraform
      port: "3010"
      health_check_url: http://localhost:3010/api/health
      health_check_timeout: 30
    secrets:
      AWS_ROLE_ARN: ${{ secrets.AWS_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
      CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
```

**Setup Instructions:**

1. **Add repository secrets** (contact infrastructure team):
   - `AWS_ROLE_ARN`: IAM role for GitHub OIDC (maimons-infra-github-ssm)
   - `EC2_INSTANCE_ID`: EC2 instance ID running services
   - `CLOUDFLARE_API_TOKEN`: Cloudflare API token

2. **Workflow behavior:**
   - Triggered on commits to main (if src, Dockerfile, or docker-compose.yml changed)
   - Runs on every push (can disable with workflow_dispatch only)
   - Reusable workflow handles: Docker build → ECR push → SSM deploy → health check → Terraform apply

3. **Monitoring:**
   - Check GitHub Actions tab for workflow status
   - Review logs for health check failures or rollbacks
   - Check CloudWatch Logs for SSM session output

## Best Practices

### Port Selection
- Use ports in the range **3000-4999** (system port protection, no conflicts)
- Update `port` in workflow, docker-compose, and Terraform to match
- Verify port is unique across all services on the EC2 instance

### Health Checks
- Define health check endpoint that returns HTTP 2xx on success
- Common patterns:
  - `/health` → simple status check
  - `/api/health` → API endpoint
  - `/ping` → lightweight response
- Deployment fails if health check doesn't pass within timeout (default: 30s)
- Test locally: `curl -i http://localhost:3010/api/health`

### Environment Variables
- Sensitive values (API keys, database passwords) → use GitHub secrets, mount to compose via `.env` file
- Non-sensitive configuration → docker-compose.yml `environment` section
- Avoid hardcoding secrets in any file committed to git

### Volumes & Persistence
- Database volumes use `driver: local` (stores on EC2 instance filesystem)
- Persistent data survives container restarts (unless volume explicitly deleted)
- First deploy creates volumes automatically
- Redeploy preserves existing volumes (only containers recreated)

### Logging
- Container logs accessible via: `docker logs mosar-api`
- SSM session logs: CloudWatch Logs (prefix: `/aws/ssm/`)
- Deployment workflow logs: GitHub Actions tab

### Rollback
- Deployment automatically rolls back if health check fails
- Manual rollback: SSM session → `docker-compose up -d` with previous IMAGE_TAG
- Contact infrastructure team if automatic rollback fails

## Validation Checklist

Before committing, verify:

- [ ] Dockerfile builds successfully: `docker build -t mosar:test .`
- [ ] docker-compose.yml is valid: `docker-compose config`
- [ ] Service starts and responds to health check locally
- [ ] Terraform validates: `terraform -chdir=terraform validate`
- [ ] Port is documented and unique (3000-4999)
- [ ] GitHub secrets are configured (AWS_ROLE_ARN, EC2_INSTANCE_ID, CLOUDFLARE_API_TOKEN)
- [ ] Health check URL is correct
- [ ] Terraform tfvars has correct tunnel ID and CNAME from maimons-infra

## Troubleshooting

**Deployment fails with "port in use"**
- Another service already uses that port
- Run: `docker ps` on EC2 instance to see active containers
- Choose a different port in 3000-4999 range
- Update Dockerfile EXPOSE, docker-compose port, workflow port, and Terraform

**Health check timeout**
- Service not responding to health check URL
- Test manually: `docker exec mosar-api curl http://localhost:3010/api/health`
- Verify health endpoint is implemented and working
- Increase health_check_timeout in workflow if startup takes longer

**Docker image not found in ECR**
- Check workflow logs for build/push step
- Verify AWS credentials are correct (check GitHub secrets)
- Ensure image tag matches (should be git SHA)

**Terraform apply fails**
- Service deployed but route not created
- Check Terraform syntax: `terraform -chdir=terraform validate`
- Verify all variables provided in terraform.tfvars
- Check Cloudflare API token has permission to create routes

## Additional Resources

- [maimons-infra Documentation](../DEPLOYMENT.md)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
- [Cloudflare Tunnel Documentation](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
