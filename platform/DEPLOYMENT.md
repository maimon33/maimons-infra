# Deployment Guide

This guide covers deploying services through the maimons-infra Cloudflare Tunnel infrastructure, including manual operations, troubleshooting, and rollback procedures.

## Overview

Services are deployed to a single EC2 instance running behind a Cloudflare Tunnel. Each service repo owns its Docker containers and Cloudflare route definitions. The GitHub Actions workflow orchestrates builds, deploys, and health checks.

**Key Components:**
- **Cloudflare Tunnel:** Single tunnel per account, routes all traffic from zones (maimons.dev, maimons.org)
- **EC2 Instance:** Runs services on localhost:3000-4999
- **GitHub Workflow:** Reusable workflow handles Docker build → push → deploy → health check → Terraform apply
- **Terraform State:** Service repos own their Cloudflare route definitions (decentralized)

## Deployment Flow

### Automatic Deployment (GitHub Actions)

When a service repo pushes to main:

1. **Docker Build & Push**
   - Build image: `docker build -t SERVICE_NAME:SHA .`
   - Push to ECR: `AWS_ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/SERVICE_NAME:SHA`

2. **Container Deployment (via SSM)**
   - Start SSM session to EC2 instance
   - Validate port is free
   - Clone/pull service repo to `/opt/services/SERVICE_NAME`
   - Set environment variable: `IMAGE_TAG=SHA`
   - Execute blue-green deploy:
     - `docker-compose down` (stop old version)
     - `docker-compose up -d` (start new version)

3. **Health Check**
   - Poll health check URL (HTTP GET) until success or timeout
   - Default timeout: 30 seconds
   - On failure: attempt rollback to previous image
   - On success: proceed to route update

4. **Terraform Apply (Cloudflare Routes)**
   - Run `terraform init && terraform apply -auto-approve`
   - Creates/updates Cloudflare tunnel route
   - Service now accessible at https://SERVICE_NAME.maimons.org

### Deployment States

| State | Meaning | Action |
|-------|---------|--------|
| **In Progress** | Workflow running | Monitor GitHub Actions logs |
| **Success** | Service deployed and healthy | Service live at public URL |
| **Health Check Failed** | Automatic rollback triggered | Check workflow logs for errors |
| **Rollback Failed** | Manual intervention required | Contact ops team, access EC2 directly |
| **Terraform Failed** | Docker OK, route not updated | Service runs locally, not accessible publicly |

## Manual Deployment & Operations

### SSH Access to EC2 Instance

**Via AWS Systems Manager Session Manager:**

```bash
# Requires: AWS CLI configured with correct credentials
aws ssm start-session \
  --target i-1234567890abcdef0 \
  --region eu-central-1
```

**Commands available:**
```bash
# View running services
docker ps

# View service logs
docker logs mosar-api -f

# Check service port
docker port mosar-api

# Verify service is accessible
curl http://localhost:3010/api/health
```

### Manual Container Deployment

If workflow fails or manual deployment needed:

```bash
# 1. Start SSM session
aws ssm start-session --target i-1234567890abcdef0 --region eu-central-1

# 2. Navigate to service directory
cd /opt/services/mosar

# 3. Verify port is free
netstat -tuln | grep 3010
# No output = port is free

# 4. Update docker-compose.yml if needed (from git pull)
git pull origin main

# 5. Set image tag (use recent git SHA or 'latest')
export IMAGE_TAG=abc123def456

# 6. Deploy (blue-green: stop old, start new)
docker-compose down
docker-compose up -d

# 7. Verify health check
curl -i http://localhost:3010/api/health
# Should return HTTP 200

# 8. Check compose status
docker-compose ps
```

### Manual Terraform Apply (Cloudflare Routes)

```bash
# 1. Start SSM session
aws ssm start-session --target i-1234567890abcdef0 --region eu-central-1

# 2. Navigate to terraform directory
cd /opt/services/mosar/terraform

# 3. Verify configuration
terraform plan

# 4. Apply changes
terraform apply -auto-approve

# 5. Verify outputs
terraform show

# 6. Verify DNS record created
curl -i https://mosar.maimons.org
```

## Troubleshooting

### Service Starts But Health Check Fails

**Symptoms:** Workflow shows health check timeout or HTTP error

**Diagnosis:**
```bash
# 1. Check if service is running
docker ps | grep mosar

# 2. Test health endpoint directly
docker exec mosar-api curl http://localhost:3010/api/health

# 3. Check service logs
docker logs mosar-api -f

# 4. Verify port binding
docker port mosar-api

# 5. Check compose status
docker-compose -f /opt/services/mosar/docker-compose.yml ps
```

**Common Causes:**
- Service takes longer to start than health_check_timeout (increase timeout in workflow)
- Health endpoint not implemented (implement /health or /api/health endpoint)
- Port mismatch (compose exposes 3010, but health check probes 3011)
- Service dependencies not ready (database/cache startup delays)
- Network issues (service can't connect to dependencies)

**Fix:**
```bash
# View service logs to identify issue
docker logs mosar-api

# If issue is slow startup, increase timeout in workflow
# Edit .github/workflows/deploy.yml: health_check_timeout: 60

# If service is crashing, check environment variables
docker inspect mosar-api | grep -A 20 Env

# Restart service
docker-compose down
docker-compose up -d
```

### Port in Use

**Symptoms:** Deployment fails with "port already in use"

**Diagnosis:**
```bash
# Find which service is using the port
lsof -i :3010
# or
netstat -tuln | grep 3010
```

**Fix:**
```bash
# Option 1: Stop the conflicting service
docker stop mosar-old
docker rm mosar-old

# Option 2: Use a different port
# Edit service repo: change docker-compose.yml, workflow, terraform
# Pick unused port in 3000-4999 range
```

### Service Container Won't Start

**Symptoms:** `docker-compose up` fails, or container exits immediately

**Diagnosis:**
```bash
# View compose error
docker-compose logs mosar-api

# Check environment variables
docker exec mosar-api env | grep NODE_ENV

# Verify image exists
docker images | grep mosar

# Test image locally
docker run -it mosar:abc123 /bin/sh
```

**Common Causes:**
- Image not in ECR (check Docker build/push in workflow logs)
- Environment variable missing (check docker-compose.yml)
- Missing dependency (database not started yet, use depends_on)
- Port conflict (port already in use by another service)

**Fix:**
```bash
# Pull latest image from ECR
docker pull AWS_ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/mosar:abc123

# Force recreate containers
docker-compose down
docker-compose pull
docker-compose up -d

# Check logs
docker-compose logs mosar-api
```

### Terraform Apply Fails

**Symptoms:** Docker deployment succeeds, Terraform apply fails, service not accessible at public URL

**Diagnosis:**
```bash
# Check terraform state
cd /opt/services/mosar/terraform
terraform plan

# View error
terraform apply -auto-approve 2>&1

# Verify credentials
terraform show

# Check Cloudflare API token
echo $TF_VAR_cloudflare_api_token
```

**Common Causes:**
- Invalid Cloudflare API token (check GitHub secrets)
- Missing tunnel ID in terraform.tfvars (get from maimons-infra outputs)
- Invalid zone ID (wrong domain configured)
- Hostname conflict (another service using same domain)

**Fix:**
```bash
# Update terraform.tfvars with correct values
# Get tunnel ID from maimons-infra:
terraform -chdir=/path/to/maimons-infra show | grep tunnel_id

# Update tfvars and retry
terraform apply -auto-approve

# Verify route was created
terraform show | grep cloudflare_record
```

### Health Check Still Failing After Fix

**Symptoms:** Service logs look OK, health endpoint responds to curl, but workflow still times out

**Diagnosis:**
```bash
# Test health endpoint exactly as workflow does
curl -v http://localhost:3010/api/health
# Check response code (should be 2xx)

# Check if service is accessible inside container
docker exec mosar-api curl http://localhost:3010/api/health

# Verify localhost is accessible (some services might need 0.0.0.0)
docker inspect mosar-api | grep -A 5 IPAddress
```

**Common Causes:**
- Service listens on 0.0.0.0 not localhost (update Dockerfile)
- Health endpoint requires auth (add auth bypass for /health)
- Service requires specific headers (update health check in workflow)
- IPv6 vs IPv4 mismatch

**Fix:**
```bash
# Ensure service listens on all interfaces (0.0.0.0)
# Update Dockerfile: change listen address to 0.0.0.0

# Rebuild and redeploy
docker build -t mosar:latest .
docker-compose down
docker-compose up -d

# Test from outside container
curl http://localhost:3010/api/health
```

## Rollback Procedures

### Automatic Rollback

The workflow automatically rolls back if health check fails:

1. Health check times out or returns non-2xx
2. Workflow retrieves previous image SHA from `.versions` file
3. Updates `IMAGE_TAG` environment variable
4. Runs `docker-compose down && docker-compose up -d` with old image
5. Re-runs health check
6. If rollback succeeds: deployment marked as failed but service stays on previous version
7. If rollback fails: alert ops, manual intervention required

### Manual Rollback

If automatic rollback fails:

```bash
# 1. Start SSM session
aws ssm start-session --target i-1234567890abcdef0 --region eu-central-1

# 2. Navigate to service directory
cd /opt/services/mosar

# 3. View version history
cat .versions
# Output:
# sha-abc123def456  (newest)
# sha-def456ghi789
# sha-ghi789jkl012

# 4. Check current version
echo $IMAGE_TAG
# or
docker ps | grep mosar-api | awk '{print $2}'

# 5. Revert to known-good version
export IMAGE_TAG=def456ghi789

# 6. Restart service
docker-compose down
docker-compose up -d

# 7. Verify health check
curl -i http://localhost:3010/api/health

# 8. Verify service accessibility
curl -i https://mosar.maimons.org
```

### Rollback Without Image Cache

If previous image is not available on EC2:

```bash
# 1. Pull image from ECR
docker pull AWS_ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/mosar:sha-def456ghi789

# 2. Tag it locally
docker tag AWS_ACCOUNT.dkr.ecr.eu-central-1.amazonaws.com/mosar:sha-def456ghi789 mosar:def456ghi789

# 3. Update environment and restart
export IMAGE_TAG=def456ghi789
docker-compose down
docker-compose up -d

# 4. Verify
curl http://localhost:3010/api/health
```

## Multi-Service Deployments

### Service Layout on EC2

```
/opt/services/
├── mosar/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── terraform/
│   ├── .versions
│   └── .env (if needed)
├── api/
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── terraform/
│   ├── .versions
│   └── .env
└── web/
    ├── Dockerfile
    ├── docker-compose.yml
    ├── terraform/
    ├── .versions
    └── .env
```

### Port Assignments

Each service uses a unique port in 3000-4999:

```
mosar api service   → localhost:3010
api service         → localhost:3020
web service         → localhost:3030
cache service       → localhost:3040 (if exposed)
```

**Port allocation table:**
- 3000-3099: Reserved
- 3100-3199: mosar project
- 3200-3299: api project
- 3300-3399: web project
- 3400-4999: Future services

### Checking All Services

```bash
# View all running containers
docker ps --format "table {{.Names}}\t{{.Ports}}\t{{.Status}}"

# Output:
# mosar-api         0.0.0.0:3010->3010/tcp   Up 2 days
# mosar-worker      -                        Up 2 days
# mosar-db          -                        Up 2 days
# api-app           0.0.0.0:3020->3020/tcp   Up 1 day
# api-cache         -                        Up 1 day
# web-app           0.0.0.0:3030->3030/tcp   Up 5 hours

# View logs for all services in a project
cd /opt/services/mosar
docker-compose logs -f

# View specific service logs
docker logs mosar-api -f

# Restart all services in a project
cd /opt/services/mosar
docker-compose restart
```

### Deploying Multiple Services

Services deploy independently (triggered by separate workflows):

**Scenario: Deploy mosar, then api**

```
Time 0:00   mosar repo push to main
            → GitHub workflow starts
            → Docker build/push
            → SSM deploy (port 3010 reserved)
            → Health check
            → Terraform apply (mosar.maimons.org created)
            → Deploy DONE at 0:05

Time 0:10   api repo push to main
            → GitHub workflow starts (independent of mosar)
            → Docker build/push
            → SSM deploy (port 3020 reserved)
            → Health check
            → Terraform apply (api.maimons.org created)
            → Deploy DONE at 0:15

Result: Both services running in parallel on EC2
        mosar.maimons.org → localhost:3010
        api.maimons.org → localhost:3020
```

**Checking concurrent deployments:**

```bash
# While api is deploying, mosar keeps running
docker ps
# Should show both mosar and api services

# Check SSM session logs (parallel sessions)
aws ssm get-command-invocations \
  --command-id abc123 \
  --region eu-central-1
```

## Cloudflare Tunnel Management

### Viewing Tunnel Status

```bash
# Via Cloudflare Dashboard:
# 1. Log in to Cloudflare
# 2. Select account
# 3. Zero Trust → Tunnels
# 4. View tunnel status, connected clients, traffic

# Via AWS Secrets Manager:
aws secretsmanager get-secret-value \
  --secret-id maimons/cloudflare-tunnel-config \
  --region eu-central-1 | jq '.SecretString | fromjson'

# Output:
# {
#   "tunnel_id": "abc123def456...",
#   "account_id": "c87c068911c8932fbedbf38dae693466",
#   "tunnel_name": "maimons-platform"
# }
```

### Verifying Routes

```bash
# Check created routes
cd /opt/services/mosar/terraform
terraform show | grep -A 5 cloudflare_tunnel_config

# Test route resolution
nslookup mosar.maimons.org
dig mosar.maimons.org +short

# Test tunnel endpoint
curl -v https://mosar.maimons.org
# Should return service response, not 404
```

### Tunnel Restart (Last Resort)

If tunnel becomes unresponsive:

```bash
# 1. Check tunnel service status
sudo systemctl status cloudflared

# 2. View tunnel logs
sudo journalctl -u cloudflared -f

# 3. If needed, restart tunnel
sudo systemctl restart cloudflared

# 4. Verify services still accessible
curl https://mosar.maimons.org
curl https://api.maimons.org
```

## Monitoring & Logging

### Service Logs

```bash
# View live logs for a service
docker logs -f mosar-api

# View logs with timestamps
docker logs --timestamps mosar-api

# View last 100 lines
docker logs --tail 100 mosar-api

# View logs since specific time
docker logs --since 2026-08-10T10:00:00Z mosar-api
```

### Workflow Logs

Accessible in GitHub Actions:

1. Go to service repo
2. Click "Actions" tab
3. Select workflow run
4. View logs for each step

**Key sections:**
- Docker build logs
- ECR push status
- SSM session output (includes compose logs)
- Health check results
- Terraform apply output

### CloudWatch Logs

SSM session output logs to CloudWatch:

```bash
# View SSM session logs
aws logs tail /aws/ssm/ --follow --region eu-central-1

# View logs for specific session
aws logs describe-log-streams \
  --log-group-name /aws/ssm/ \
  --region eu-central-1 | jq '.logStreams[0].logStreamName'

# Filter by service name
aws logs tail /aws/ssm/ --follow --filter-pattern mosar --region eu-central-1
```

## Pre-Deployment Checklist

Before deploying a new service:

- [ ] Service repo has Dockerfile, docker-compose.yml, terraform/
- [ ] Dockerfile builds successfully locally
- [ ] Service responds to health check endpoint
- [ ] Port is assigned and unique (3000-4999)
- [ ] GitHub secrets configured (AWS_ROLE_ARN, EC2_INSTANCE_ID, CLOUDFLARE_API_TOKEN)
- [ ] Terraform validates: `terraform -chdir=terraform validate`
- [ ] terraform.tfvars has correct tunnel ID and CNAME from maimons-infra
- [ ] Service repo workflow file calls maimons-infra reusable workflow
- [ ] Domain/subdomain not already in use (check Cloudflare dashboard)

## Post-Deployment Verification

After deployment succeeds:

```bash
# 1. Check service is running
docker ps | grep SERVICE_NAME

# 2. Verify health endpoint
curl http://localhost:PORT/api/health

# 3. Test public URL
curl -i https://SERVICE_NAME.maimons.org

# 4. Check Cloudflare route
cd /opt/services/SERVICE_NAME/terraform
terraform show | grep hostname

# 5. Verify DNS
dig SERVICE_NAME.maimons.org +short
```

## Common Mistakes

**Mistake 1: Hardcoding PORT in docker-compose.yml**
- Service deploys but health check fails when PORT changes
- Fix: Use environment variable `${SERVICE_PORT}` or rely on IMAGE_TAG variable

**Mistake 2: Multiple services on same port**
- Deployment fails with "port in use"
- Fix: Verify port is unique in EC2, update to different port in workflow/compose/terraform

**Mistake 3: Forgetting to update terraform.tfvars**
- Service runs but not accessible publicly (Terraform apply fails)
- Fix: Copy tunnel ID and CNAME from maimons-infra, update terraform.tfvars

**Mistake 4: Health check endpoint requires auth**
- Service is healthy but workflow doesn't see it (health check fails)
- Fix: Add `/health` endpoint without auth, or bypass auth for `/health`

**Mistake 5: Service takes >30 seconds to start**
- Health check times out on new deployments
- Fix: Increase health_check_timeout in workflow to 60 or 90 seconds

## Escalation & Support

**For issues that don't resolve with above steps:**

1. Collect logs:
   - GitHub workflow logs (full run)
   - SSM session logs (from CloudWatch)
   - Docker service logs (`docker logs SERVICE_NAME`)
   - Terraform apply output

2. Check status:
   - Cloudflare tunnel status (is tunnel connected?)
   - EC2 instance status (is it running?)
   - Port availability (is port free on EC2?)

3. Contact infrastructure team with:
   - Service name and deployment time
   - Exact error message from workflow/SSM/logs
   - What manual steps were attempted

## Additional Resources

- [Service Repository Template](../docs/SERVICE_REPO_TEMPLATE.md)
- [maimons-infra README](../README.md)
- [Cloudflare Tunnel Docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
