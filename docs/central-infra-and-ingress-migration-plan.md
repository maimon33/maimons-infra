# Central EC2 Infrastructure and Shared Ingress Migration Plan

## Purpose

Move ownership of the shared EC2 host and its supporting infrastructure into a dedicated Terraform repository. Replace the host-level NGINX configuration currently owned by the Mosar repository with centrally managed shared ingress that can serve Mosar and additional projects.

This plan preserves the existing Mosar application while establishing a clear boundary between platform infrastructure and application deployment.

## Current architecture

```text
Visitor
  -> Cloudflare DNS, TLS, and Access
  -> EC2 public port 80 over HTTP
  -> host-level NGINX
  -> 127.0.0.1:3010
  -> Mosar Express and React container
  -> SQLite data under /opt/mosar/data
  -> S3 backups and media
```

The current deployment process:

1. Builds the React application locally.
2. Copies the repository and built files to `/opt/mosar` over SSH and `rsync`.
3. Writes application secrets and long-lived AWS credentials into `/opt/mosar/.env`.
4. Builds the Docker image on EC2.
5. Removes the running Mosar container.
6. Starts the replacement container using host networking.
7. Reloads NGINX.
8. Restores SQLite from S3 when necessary and creates a new backup.

### Current NGINX responsibilities

NGINX currently provides only:

- hostname routing for `mosar.maimons.org`;
- forwarding to Express on port `3010`;
- a 25 MB request-body limit;
- forwarded host, protocol, and client-address headers;
- a 5-second connection timeout;
- 300-second read and send timeouts;
- optional WebSocket upgrade headers, although Mosar currently has no known WebSocket routes.

There is no application-specific NGINX behavior that prevents replacement with another reverse proxy.

## Target architecture

```text
Visitor
  -> Cloudflare DNS, Access, and TLS
  -> shared ingress on EC2
  -> shared private Docker edge network
  -> Mosar container on port 3010
  -> other project containers on their own internal ports

Central infrastructure repository
  -> Terraform backend
  -> EC2, networking, storage, IAM, and security groups
  -> shared ingress
  -> Cloudflare origin configuration
  -> host bootstrap and observability
  -> deployment roles
  -> published platform contract

Application repositories
  -> build versioned container images
  -> declare hostname, internal port, health path, and resource needs
  -> deploy through a narrowly scoped role
  -> do not manage the EC2 host or shared ingress process
```

## Recommended ingress

Use Traefik as the shared ingress service.

Traefik is the preferred option because the host is intended to serve multiple independently deployed Docker projects. It supports Docker-aware routing, explicit opt-in exposure, health-aware services, request middleware, and configuration reloads without coupling application deployments to a host package manager.

Recommended base policy:

- run Traefik as a centrally managed container;
- pin the image to an explicit supported version;
- set `exposedByDefault=false`;
- expose only port 80 to Cloudflare's published IPv4 and IPv6 ranges;
- attach Traefik and public applications to one externally created Docker network, such as `edge`;
- do not publish application ports on the EC2 host;
- require an explicit route declaration for every exposed container;
- keep the Traefik dashboard disabled publicly;
- protect Docker API access with a restricted socket proxy or another hardened access method;
- enable access logs and metrics centrally.

### Routing ownership choice

Two models are possible:

1. **Application-owned labels:** each project declares its hostname and middleware through Docker labels. This provides easy self-service deployment.
2. **Central route catalog:** the infrastructure repository contains the approved hostname-to-service mappings, and Traefik reads generated dynamic configuration. This provides stronger central control.

Use a central route catalog if hostname ownership must be reviewed centrally. Application-owned labels are acceptable when every repository with deployment access is equally trusted. A hybrid is also possible: application repositories declare metadata while a central pipeline validates and renders the final routes.

## Infrastructure repository ownership

The central infrastructure repository should own the following resources and configuration.

### Terraform foundation

- Terraform and provider version constraints;
- encrypted, versioned S3 backend;
- S3 state locking with `use_lockfile = true`;
- narrowly scoped state read and write IAM policies;
- provider lock file committed to source control;
- formatting, validation, linting, and security checks in CI.

### AWS resources

- EC2 instance or launch definition;
- Elastic IP when using direct public ingress;
- VPC, subnet, route, and security-group rules within the chosen scope;
- encrypted EBS volumes and attachment policy;
- EC2 instance profile and IAM role;
- Systems Manager connectivity and permissions;
- backup bucket and lifecycle policies where centrally owned;
- monitoring and alerting resources;
- deployment roles assumable by application CI.

### Host bootstrap

- Docker Engine and Compose plugin installation;
- creation of the shared `edge` Docker network;
- Traefik installation;
- persistent application directory conventions;
- log rotation and disk monitoring;
- Grafana Alloy or equivalent observability agent;
- Systems Manager agent and session access;
- operating-system update policy.

### Cloudflare

- DNS records or Tunnel hostname routes;
- proxied Cloudflare DNS with edge TLS and HTTP-only origin transport;
- Cloudflare Access applications and policies;
- cache behavior appropriate to each application;
- origin protection and certificate configuration.

Avoid changing a zone-wide TLS setting to accommodate one legacy origin without verifying every hostname in the zone.

## State and cross-repository contract

Do not use the primary infrastructure state file as a general service registry.

Terraform's `terraform_remote_state` data source exposes root outputs, but a consumer must have permission to retrieve the complete state snapshot. Infrastructure state can contain sensitive resource attributes even when those attributes are not declared as outputs.

### Recommended contract

Publish selected, non-sensitive values to AWS Systems Manager Parameter Store or another deliberately scoped configuration registry. Example names:

```text
/platform/prod/aws_region
/platform/prod/instance_id
/platform/prod/deploy_role_arn
/platform/prod/edge_network
/platform/prod/sites/mosar/hostname
/platform/prod/sites/mosar/service_name
/platform/prod/sites/mosar/internal_port
/platform/prod/sites/mosar/health_path
```

Application repositories receive read access only to the parameters they need.

If remote state is still required, create a small, separate contract state containing only non-sensitive published resources and outputs. Do not grant application repositories read access to the main platform state.

### Desired state versus runtime state

Terraform should describe desired infrastructure and approved site registrations. It should not be treated as authoritative live deployment status.

Use health checks and monitoring for runtime facts such as:

- which container image is currently running;
- whether a service is healthy;
- application uptime;
- current response status and latency;
- disk and memory pressure.

## Secret-management requirements

Before or during the migration:

1. Revoke and rotate the Grafana Cloud credential currently committed in the Mosar deployment script.
2. Remove the credential from the working tree and Git history.
3. Stop copying AWS access keys to the EC2 host.
4. Grant Mosar S3 access through the EC2 instance role.
5. Store AI, Cloudflare, and third-party application secrets in SSM Parameter Store or Secrets Manager.
6. Materialize application environment files only when required, with owner-only permissions.
7. Give every application and deployment pipeline least-privilege IAM permissions.
8. Prefer CI identity federation through OpenID Connect over static CI credentials.

The Mosar application currently performs Cloudflare cache purges itself. Consider replacing its zone-wide token with a narrowly scoped token, or moving purge behavior into the central deployment workflow.

## Mosar repository changes

The Mosar repository should retain ownership of the application but give up host administration.

### Production container configuration

- remove `network_mode: host`;
- remove production host port publication for `3010`;
- attach the Mosar service to the external `edge` network;
- expose port `3010` only to that Docker network;
- add an explicit container health check using `/api/health`;
- add the approved Traefik route and middleware metadata, unless routes are generated centrally;
- retain persistent mounts for `/app/data` and `/app/content`;
- retain appropriate memory and logging limits;
- consume a versioned image from a container registry instead of building on EC2.

### Mosar route behavior to preserve

- hostname: `mosar.maimons.org`;
- internal service port: `3010`;
- health endpoint: `/api/health`;
- maximum request body: 25 MiB, or `26214400` bytes;
- upstream operations may run for up to 300 seconds;
- original host and forwarding headers must be preserved;
- SPA fallback must continue to be handled by Express;
- Cloudflare Access behavior must be verified for both public and administrative paths.

### Deployment workflow

Replace SSH source synchronization and remote image builds with:

1. run tests;
2. build one immutable container image;
3. tag it with the Git commit and, optionally, a release tag;
4. push it to ECR, GHCR, or another chosen registry;
5. assume the Mosar deployment role;
6. instruct the host through Systems Manager or a central deployment runner to pull the exact image digest;
7. start the new container;
8. wait for a passing health check;
9. verify the public health endpoint;
10. retain or restore the prior image on failure;
11. create and verify the database backup according to the selected backup policy.

The deployment should fail when the new container is unhealthy. A failed backup or restore should not be silently reported as a successful deployment.

## Migration phases

### Phase 0: secure the current system

- rotate the exposed Grafana credential;
- remove committed secrets;
- audit `/opt/mosar/.env` permissions;
- confirm the EC2 security group does not expose port `3010` publicly;
- record the current instance ID, volumes, security groups, IAM associations, public IP, DNS records, and Cloudflare policies;
- create and test a current Mosar database backup.

### Phase 1: create the infrastructure repository

- bootstrap the Terraform backend;
- define provider and Terraform versions;
- import the existing EC2 and supporting resources rather than recreating them;
- generate a plan showing no unexpected replacements;
- add the instance role, Systems Manager access, and state contract;
- document ownership and emergency access procedures.

No existing stateful EC2 resource should be replaced during import without an explicit migration decision and a verified backup.

### Phase 2: deploy shared ingress beside NGINX

- create the external `edge` Docker network;
- run Traefik on temporary host ports so NGINX can continue serving production;
- configure logging, metrics, and health checks;
- configure the Mosar hostname route and 25 MiB middleware;
- test routing locally with the expected `Host` header;
- confirm long-running requests, uploads, static assets, and API calls.

### Phase 3: adapt Mosar networking

- create a production Compose definition that uses the shared edge network;
- remove host networking and published application ports;
- add a health check;
- deploy the Mosar image through the new workflow;
- allow temporary parallel validation without changing public DNS.

### Phase 4: cut over ingress

For direct Cloudflare ingress:

1. restrict origin port 80 to Cloudflare's published IP ranges;
2. verify HTTP routing locally with the expected Host header and HTTPS through Cloudflare;
3. stop NGINX;
4. bind Traefik to port 80;
5. retain Cloudflare edge HTTPS with Flexible origin mode;
6. verify public and administrative flows;
7. keep the NGINX package and configuration available for a short rollback window.

### Phase 5: remove legacy ownership from Mosar

- remove NGINX installation and reload commands;
- remove EC2 IP, SSH username, and key-path constants;
- remove security-group mutation commands;
- remove host Docker installation and monitoring installation commands;
- remove direct Cloudflare DNS and Access provisioning;
- remove source synchronization and remote image builds;
- update Mosar deployment documentation and operator menu;
- retain application-specific backup, status, and log commands only through the new platform interface.

## Validation checklist

### Infrastructure

- Terraform state is encrypted, versioned, locked, and access-controlled.
- Import produces no unintended EC2 or volume replacement.
- EC2 uses an instance role instead of stored AWS access keys.
- Systems Manager access works before SSH access is reduced.
- Disk, memory, container health, and ingress errors are monitored.
- Applications cannot expose themselves accidentally.

### Ingress

- `https://mosar.maimons.org` serves the expected application.
- direct access to port `3010` is impossible externally.
- requests larger than 25 MiB receive HTTP 413.
- valid near-limit uploads succeed.
- operations approaching 300 seconds are not terminated prematurely.
- forwarded protocol and client address behavior is correct.
- the Traefik dashboard is not public.
- unknown hostnames receive no application route.

### Mosar

- `/api/health` passes before traffic is accepted.
- React SPA routes work on direct navigation and refresh.
- admin authentication and Cloudflare Access behavior are correct.
- content edits, uploads, AI operations, media, and cache purges work.
- SQLite persists across container replacement.
- backup creation and restore are tested.
- rollback to the previous image is tested.

## Rollback strategy

During ingress migration, preserve the existing NGINX configuration and package.

If the cutover fails:

1. stop the Traefik listener on port 80;
2. restart NGINX;
3. restore the prior Mosar Compose configuration if networking changed;
4. start the last known-good Mosar image;
5. restore Cloudflare DNS or TLS settings when they changed;
6. verify the public health endpoint and administrative functions.

Do not destroy imported Terraform resources as a rollback mechanism. Rollback should change traffic and application versions, not delete the underlying host or data volumes.

## Decisions required before implementation

1. Use application-owned Traefik labels or a central route catalog?
2. Use ECR, GHCR, or another container registry?
3. Deploy through Systems Manager, a self-hosted runner, or a central deployment service?
4. Keep application data on host-mounted EBS paths or adopt named Docker volumes backed by EBS?
5. Keep Cloudflare cache purging inside Mosar or move it to the deployment platform?
6. Protect only `/admin` or the complete Mosar hostname with Cloudflare Access?
7. Preserve the existing EC2 instance long-term or treat it as an import-and-transition source for a reproducible replacement host?

## Recommended initial decisions

For the first migration iteration:

- import and preserve the current EC2 instance;
- use Traefik as the shared ingress;
- use a central route catalog for reviewed hostname ownership;
- retain proxied direct Cloudflare ingress over restricted HTTP initially;
- use an encrypted and versioned S3 Terraform backend with S3 locking;
- publish the cross-repository contract through SSM Parameter Store;
- use the EC2 instance role for S3 access;
- use a container registry and Systems Manager for deployments;
- preserve `/opt/<application>` EBS-backed persistent directories during the first migration;
- remove host networking and all public application ports.

This sequence replaces NGINX without combining that cutover with an unnecessary stateful host replacement.
