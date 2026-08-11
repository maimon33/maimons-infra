# Known Limitations and Scope Boundaries

This document outlines the intentional scope boundaries of the maimons-infra Cloudflare Tunnel Service Deployment system.

## Infrastructure Constraints

### Single EC2 Instance 
- **Limitation:** All services run on a single EC2 instance
- **Scope:** No load balancing, no automatic scaling, no multi-region deployment
- **Implication:** Single instance is a single point of failure; scaling requires vertical (larger instance) not horizontal (more instances)
- **Workaround:** For high availability, implement external load balancer or failover mechanism separately

### Port Range Restriction
- **Limitation:** Services can only bind to ports 3000-4999
- **Scope:** This protects system ports (< 3000) and prevents conflicts
- **Implication:** Maximum ~2000 services can run simultaneously (realistic: ~20-50 given memory/CPU constraints)
- **Planning:** Allocate ports explicitly:
  - 3000-3099: Reserved
  - 3100-3199: mosar project
  - 3200-3299: api project
  - 3300-3399: web project
  - 3400-4999: Future services

### Tunnel Configuration
- **Limitation:** Single Cloudflare Tunnel per account (not per zone)
- **Scope:** Tunnel is account-level, independent of zones (maimons.dev, maimons.org)
- **Implication:** All traffic from all zones flows through one tunnel; single tunnel failure affects all zones
- **Design Choice:** Simplifies tunnel management; route filtering happens at cloudflare_tunnel_config level

## Deployment Constraints

### Manual Tunnel ID Setup
- **Limitation:** Service repos must manually configure tunnel ID and CNAME
- **Scope:** No automatic tunnel ID discovery or dynamic secret injection
- **Implication:** Service repos depend on maimons-infra outputs (tunnel ID, CNAME) passed manually
- **Process:**
  1. Run `terraform -chdir=environments/prod show` in maimons-infra
  2. Copy tunnel ID and CNAME to service repo terraform.tfvars
  3. No runtime secret manager integration (secrets are infrastructure outputs)
- **Workaround:** Store outputs in GitHub repository secrets or GitHub environment variables

### Blue-Green Deployment Only
- **Limitation:** No canary deployments, no rolling updates, no gradual traffic shifting
- **Scope:** Deployment is binary: down → up
- **Strategy:** 
  1. `docker-compose down` (stop old version, break all active connections)
  2. `docker-compose up -d` (start new version)
  3. Health check to verify startup
  4. Rollback if health check fails
- **Implication:** ~5-30 seconds of downtime per deployment (depends on service startup time)
- **Impact:** Not suitable for zero-downtime deployments

### Health Check Limitations
- **Limitation:** Health checks are HTTP endpoint only (GET request to URL)
- **Scope:** No TCP probes, no custom scripts, no multi-endpoint health checks
- **Requirements:**
  - Service must expose HTTP endpoint returning 2xx on success
  - Endpoint must be reachable at `localhost:PORT` from EC2 instance
  - No authentication (public health endpoint)
- **Timeout:** Fixed per deployment (default 30s); requires workflow update to change
- **Failure:** Health check failure triggers automatic rollback; no alert sent

## Secrets Management

### Decentralized Secrets (Service Repo Responsibility)
- **Limitation:** No centralized secrets management; each service repo manages its own secrets
- **Scope:** maimons-infra only manages tunnel credentials (stored in AWS Secrets Manager)
- **Service Secrets:** Each service repo is responsible for:
  - Database passwords
  - API keys
  - Configuration tokens
  - Any sensitive environment variables
- **Pattern:** Service repos pass secrets to docker-compose via:
  - `.env` files (local, not committed)
  - GitHub Actions secrets → environment variables
  - AWS Secrets Manager/Parameter Store (optional, per service)
- **Risk:** No audit trail, no centralized rotation policy

### Cloudflare API Token Management
- **Scope:** GitHub Actions secrets only (GitHub Actions → EC2 → Terraform)
- **Limitation:** No automatic token rotation
- **Manual Rotation:** Required when token is refreshed (update all service repos' GitHub secrets)

## Feature Constraints

### No Secrets Rotation
- **Limitation:** Secrets are static; no automatic rotation
- **Manual Process:** Update secrets in GitHub, redeploy services
- **Impact:** Long-lived credentials increase security risk

### No Centralized Observability
- **Limitation:** Logs are distributed across multiple sources
- **Sources:**
  - GitHub Actions (deployment logs)
  - CloudWatch (SSM session logs)
  - Docker logs (service logs, requires EC2 access)
  - Cloudflare dashboard (tunnel traffic)
- **Implication:** Debugging requires checking multiple places; no unified dashboard

### No Distributed Tracing
- **Limitation:** No cross-service tracing, no request correlation IDs
- **Scope:** Services are isolated containers; no shared context
- **Workaround:** Implement logging and correlation IDs within service code

### No Service Discovery
- **Limitation:** Services cannot discover other services dynamically
- **Scope:** All inter-service communication must use hardcoded URLs or manual configuration
- **Example:** Service A connecting to Service B requires knowing `http://localhost:3020` or `https://api.maimons.org`
- **Constraint:** No dynamic service mesh, no DNS-based discovery

### No API Gateway
- **Limitation:** No rate limiting, request validation, or centralized routing logic
- **Scope:** Cloudflare tunnel routes to services directly
- **Rate Limiting:** Must be implemented per-service using Cloudflare Workers or service code

## Scaling and Performance

### No Load Balancing
- **Limitation:** Single instance serves all traffic; no request distribution
- **Implication:** Instance resources (CPU, memory, disk) are shared across all services
- **Planning:** Monitor resource usage; vertical scaling (larger instance) required before hitting limits

### No Caching Layer
- **Limitation:** No HTTP caching, no response deduplication
- **Scope:** Each request goes directly to service container
- **Workaround:** Implement caching in service code or use Cloudflare cache rules

### No Database Replication
- **Limitation:** No database failover, no read replicas
- **Scope:** Each service runs its own database (if using one)
- **Risk:** Database failure is service failure; no automatic recovery

## Operational Limitations

### No Automated Monitoring Alerts
- **Limitation:** Deployment failures don't trigger alerts
- **Detection:** Manual check of GitHub Actions logs required
- **Workaround:** Subscribe to GitHub Actions notifications or use third-party tools (GitHub status checks)

### No Automated Rollback Restoration
- **Limitation:** Automatic rollback succeeds silently; failed deployments don't notify ops
- **Manual Follow-up:** Ops must investigate why new version failed

### No Deployment Approval Gates
- **Limitation:** All commits to main trigger immediate deployment
- **Scope:** No manual approval or staging environment
- **Risk:** Failed tests or breaking changes deployed directly to production
- **Workaround:** Enforce PR reviews before main merge; implement branch protection rules

### No Scheduled Deployments
- **Limitation:** Deployments triggered on push only (not on schedule)
- **Workaround:** Use `workflow_dispatch` for manual deployment, GitHub Actions schedule_workflow for scheduled runs

## Documentation and Training

### Limited Observability Documentation
- **Limitation:** No dashboard or centralized monitoring guide
- **Provided:** Troubleshooting guides for common issues (logs access, health checks, rollback)

## Future Enhancements (Out of Scope)

These features are intentionally not included in the current implementation:

### Multi-Instance Deployment
- [ ] Load balancer (AWS ELB/ALB) with auto-scaling groups
- [ ] Service distribution across multiple EC2 instances
- [ ] Health checks at instance level, not just service level
- [ ] Requires: Terraform changes to infra, GitHub workflow changes to coordinate deployments

### Kubernetes Migration
- [ ] Replace EC2 + Docker Compose with EKS clusters
- [ ] Service discovery via Kubernetes DNS
- [ ] Rolling updates, canary deployments, traffic shifting
- [ ] Helm charts for service templating
- [ ] Requires: Complete rewrite of deployment workflow, service repos migration

### Advanced Deployment Strategies
- [ ] Canary deployments (10% traffic to new version)
- [ ] Rolling updates (gradual container restart)
- [ ] Blue-green with traffic shifting (not instant cutover)
- [ ] A/B testing framework
- [ ] Requires: Load balancer, traffic shifting logic, extended health checks

### Service Discovery and Mesh
- [ ] Consul for dynamic service discovery
- [ ] Istio service mesh (traffic management, retries, circuit breakers)
- [ ] Envoy sidecars for inter-service communication
- [ ] Requires: Mesh controller, sidecar injection, traffic policies

### Centralized Secrets Management
- [ ] HashiCorp Vault for secret rotation
- [ ] AWS Secrets Manager integration (cross-service)
- [ ] Automatic credential refresh and application reload
- [ ] Audit logging of secret access
- [ ] Requires: Vault infrastructure, agent on EC2, service code changes

### Advanced Monitoring and Observability
- [ ] Prometheus for metrics collection
- [ ] Grafana dashboards for visualization
- [ ] Distributed tracing (Jaeger)
- [ ] Centralized logging (ELK, Datadog, New Relic)
- [ ] Alert rules and on-call escalation
- [ ] Requires: Monitoring infrastructure, instrumentation in services

### API Gateway and Rate Limiting
- [ ] AWS API Gateway for request validation
- [ ] Cloudflare Workers for request transformation
- [ ] Request rate limiting per IP/API key
- [ ] Request authentication and authorization
- [ ] Requires: Gateway configuration, authentication service, policy engine

### Database High Availability
- [ ] RDS with Multi-AZ replication
- [ ] Read replicas for scaling
- [ ] Automated backups and point-in-time recovery
- [ ] Requires: Database migration, connection pooling updates

---

## Summary Table

| Feature | Current State | Limitation | Workaround |
|---------|---------------|-----------|-----------|
| Instances | 1 | No scaling, single point of failure | Upgrade instance size, implement external failover |
| Deployment | Blue-green | Downtime (~10s), no gradual rollout | Implement canary with load balancer |
| Services | ~20-50 | Limited by instance resources and ports | Multi-instance deployment |
| Health Checks | HTTP endpoint | No custom probes, public endpoint required | Implement health endpoint in service |
| Secrets | Decentralized | No rotation, no audit | Service-specific rotation policy |
| Observability | Distributed logs | Manual log access, no dashboard | Centralized logging (ELK/Datadog) |
| Alerts | None | Manual failure detection | GitHub Actions notifications, custom webhook |
| Routes | Manual setup | Tunnel ID hardcoded in service repos | Automate via CI/CD or GitHub secrets |

---

## Scope Assumptions

1. **Workload Size:** Small to medium (< 20 services, < 2GB memory per service)
2. **Availability Requirement:** Best-effort (not 99.99%), acceptable downtime during deployments
3. **Geographic Scope:** Single region (eu-central-1), single account
4. **Team Size:** Ops team manages infrastructure, service teams handle deployments
5. **Compliance:** No PCI, HIPAA, or SOC2 requirements (no audit logging, no encryption at rest)

---

## Revision History

- **2026-08-10:** Initial scope documentation created during Task 6 validation
