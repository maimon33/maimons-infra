# Adding New Services to maimons-infra

This guide explains how to add a new application and make it accessible through the Cloudflare tunnel with proper routing and access control.

## Prerequisites

- Access to this repository
- Your application ready to run on the EC2 instance
- Cloudflare domain configured in maimons-infra
- Your email address for Cloudflare Access

## Step 1: Define the Service

Add your service to `environments/prod/local.auto.tfvars` in the `services` map:

```hcl
services = {
  monitoring = { ... existing ... }
  mosar = { ... existing ... }
  my-app = {
    access_emails = ["your-email@example.com", "team@example.com"]
    access_path   = "/"
    health_path   = "/healthz"
    hostname      = "my-app.maimons.dev"
    internal_port = 3003
    service_name  = "my-app"
  }
}
```

### Service Configuration

| Field | Required | Description |
|-------|----------|-------------|
| `access_emails` | Yes | List of email addresses allowed via Cloudflare Access |
| `access_path` | Yes | URL path to protect with Access (usually `/`) |
| `health_path` | Yes | Health check endpoint (e.g., `/healthz` or `/health`) |
| `hostname` | Yes | Full domain name (must match a maimons.dev or maimons.org zone) |
| `internal_port` | Yes | Port your app listens on inside the container/EC2 (typically 3000-3999) |
| `service_name` | Yes | Service identifier (lowercase, alphanumeric, used for DNS and logging) |

## Step 2: Update Terraform

```bash
cd environments/prod
terraform plan
terraform apply
```

This automatically creates:
- ✅ Cloudflare DNS CNAME record (proxied through Cloudflare edge)
- ✅ Cloudflare Access application for email-based auth
- ✅ Tunnel ingress rule routing `hostname` → `http://127.0.0.1:internal_port`

## Step 3: Deploy Your Application

Your app must be running on the EC2 instance on the configured port before traffic reaches it.

### Option A: Docker (Recommended)

1. Add service to `platform/compose.yaml`:

```yaml
services:
  my-app:
    build:
      context: ./my-app/app
    container_name: platform-my-app
    ports:
      - "127.0.0.1:3003:3003"
    networks:
      - app-egress
    mem_limit: 512m
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3003/healthz"]
      interval: 15s
      timeout: 5s
      retries: 3
    restart: unless-stopped
```

2. Deploy via GitHub Actions or SSM:

```bash
aws ssm send-command \
  --instance-ids i-0103a5cecf6618658 \
  --document-name AWS-RunShellScript \
  --parameters 'commands=["cd /opt/platform && docker-compose up -d my-app"]'
```

### Option B: Direct EC2 Service

Create a systemd service or run your app directly on the port.

## Step 4: Verify Connectivity

1. **From EC2 instance:**
```bash
# SSH into EC2
aws ssm start-session --target i-0103a5cecf6618658

# Test internal routing
curl http://127.0.0.1:3003/healthz
```

2. **Through tunnel:**
```bash
# From your local machine
curl https://my-app.maimons.dev/
# Should redirect to Cloudflare Access login
```

3. **After Cloudflare Access login:**
- You'll be authenticated with your email
- Tunnel routes to your app
- Traffic flows: GitHub Actions → Cloudflare Edge → Tunnel → App on EC2

## Important Notes

### Ports
- **1-1000:** Reserved system ports, avoid
- **3000-3999:** Recommended range for applications
- **20241:** Reserved for tunnel metrics (`/metrics` endpoint)
- **20242+:** Safe for additional services

### Networking
- Apps MUST bind to `127.0.0.1` (localhost), not `0.0.0.0`
- The tunnel accesses them via `http://127.0.0.1:port`
- HTTPS is handled by Cloudflare, your app uses plain HTTP
- IPv4 and IPv6 both supported through Cloudflare edge

### Health Checks
- The `health_path` must return HTTP 200
- Used by Docker health checks to monitor the service
- Separate from Cloudflare's health monitoring

## Path-Based Access Control

To protect different paths with different email restrictions, use the optional `access_paths` field:

```hcl
mosar = {
  internal_port = 3001
  hostname      = "mosar.maimons.org"
  health_path   = "/healthz"
  service_name  = "mosar"
  access_emails = ["default@example.com"]  # Fallback/default
  access_path   = "/"
  # NEW: Path-based access policies
  access_paths = {
    "/"       = []                                    # Public root
    "/admin"  = ["admin@example.com"]                # Admin restricted
    "/api"    = ["api-user@example.com"]             # API restricted
  }
}
```

When `access_paths` is defined:
- ✅ Creates separate Cloudflare Access applications per path
- ✅ Each path can have different email restrictions
- ✅ Empty email list = public access for that path
- ✅ Non-empty list = restricted to those emails
- ✅ All routes to the same backend service

This allows granular control: e.g., `/api` public but `/admin` protected, all on one service.

### Session Duration
- Default: 30 days (configured in Terraform)
- Users stay logged in after Cloudflare Access authentication
- Adjust `session_duration` in `cloudflare-access.tf` if needed

## Troubleshooting

### 404 Error After Cloudflare Login
- Check tunnel ingress rules: `terraform plan` should show your hostname
- Verify app is running on correct port: `curl http://127.0.0.1:3003`
- Check cloudflared is running: `systemctl status cloudflared`

### DNS Not Resolving
- Verify DNS record was created in Cloudflare dashboard
- Should be CNAME record with "proxied" (orange cloud) enabled
- Wait 5 minutes for DNS propagation

### App Not Responding
- Check logs: `docker logs platform-my-app` or journalctl for systemd services
- Verify health endpoint works: `curl http://127.0.0.1:3003/healthz`
- Check firewall/security groups allow traffic

### Connection Timeout
- Ensure app is listening on 127.0.0.1 (not 0.0.0.0)
- Check port number matches `internal_port` in config
- Verify tunnel is running: `systemctl status cloudflared`

## Example: Adding a Simple Node.js App

```hcl
# Step 1: local.auto.tfvars
services = {
  # ... existing services ...
  api = {
    access_emails = ["developer@example.com"]
    access_path   = "/"
    health_path   = "/status"
    hostname      = "api.maimons.dev"
    internal_port = 3004
    service_name  = "api"
  }
}
```

```yaml
# Step 2: platform/compose.yaml
services:
  api:
    build:
      context: ./api/app
    container_name: platform-api
    ports:
      - "127.0.0.1:3004:3004"
    environment:
      PORT: 3004
    networks:
      - app-egress
    mem_limit: 512m
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3004/status"]
      interval: 15s
      timeout: 5s
      retries: 3
    restart: unless-stopped
```

```bash
# Step 3: Deploy
terraform apply  # Creates DNS + Cloudflare Access
docker-compose up -d api  # Starts the app
```

## Workflow for External Repos

If adding services from another repository:

1. **Create PR in maimons-infra** with service definition in `local.auto.tfvars`
2. **CI approves** terraform plan
3. **Merge PR** → Terraform apply runs → DNS + Access created
4. **External repo deploys** their app to the EC2 instance

This keeps routing centralized while allowing other repos to manage their own deployments.
