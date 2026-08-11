# Simple platform monitoring

The platform includes a small, read-only dashboard at
`https://monitor.maimons.dev`. It is one Python application with no database and
no monitoring framework. It reads live data from three sources:

- the Docker Engine API, through a GET-only socket proxy;
- the local cloudflared metrics endpoint;
- Cloudflare GraphQL Analytics, refreshed every five minutes.

The page shows container state, CPU, memory, network counters and image names;
Tunnel connection, stream, request and error counters; and trailing 24-hour
requests, visits, and edge response volume by hostname.

Cloudflare defines a visit as a page view reached from a different referrer or a
direct link. It is not a unique-visitor count. GraphQL values are operational
analytics and are not billing measurements.

## Access and routing

The monitoring service is present in the example central service catalog with
`access_path = "/"`. Terraform creates:

- an orange-cloud CNAME to the shared Tunnel;
- a Tunnel ingress rule that forwards the hostname directly to
  `http://localhost:3001`;
- a Cloudflare Access application covering the complete hostname;
- an allow policy containing only the configured operator email addresses.

The dashboard publishes port 3001 only on host loopback, so cloudflared can
reach it but remote clients cannot bypass Cloudflare Access. The supporting
Docker API proxy exists only on the internal `platform-monitoring` network.
The dashboard container is limited to 256 MiB of memory and the Docker API
proxy to 64 MiB.

## Configure infrastructure

1. Create a dedicated Cloudflare API token with `Zone Analytics Read` for the
   selected zone. Do not reuse the Tunnel management token.
2. Add `monitoring/runtime` to `service_secret_names`, and add the monitoring
   entry from `platform/monitoring/terraform.tfvars.example` to the production
   `services` value. Replace `REPLACE_WITH_OPERATOR_EMAIL` with every email that
   may sign in. Keep `access_path = "/"` so the entire hostname is screened.
3. Add this repository's production-environment identity to
   `github_repository_subjects.monitoring`:

   ```hcl
   monitoring = ["repo:maimon33/maimons-infra:environment:production"]
   ```

4. From `platform/monitoring`, initialize, review, and apply the production
   Terraform plan:

   ```bash
   terraform init -backend-config=backend.hcl
   terraform plan
   terraform apply
   ```

   This operational root uses the canonical production definitions and the
   same remote state. It creates the ECR repository, service-specific
   deployment role, runtime secret container, orange-cloud DNS record, Tunnel
   route, and Access policy.
5. Put the JSON shape from
   `platform/monitoring/runtime-secret.example.json` into the created
   `/platform/prod/monitoring/runtime` secret. Terraform intentionally does not
   manage the secret value.
6. In the GitHub `production` environment, set `AWS_ROLE_ARN` to the
   `monitoring` entry in the Terraform `deployment_role_arns` output and set
   `EC2_INSTANCE_ID` to the Terraform `instance_id` output.
7. For the existing host, run `modules/ec2-startup/cloudflared-startup.sh` once
   as root through Systems Manager. New hosts run it from user data. This step is
   required because changing EC2 user data does not rerun cloud-init on an
   existing instance.

## Deploy

The `Deploy Monitoring` workflow builds an immutable image, pushes it to the
central `monitoring` ECR repository, and uses Systems Manager to update the
shared host. It runs for monitoring changes merged to `main`, and it can also be
started manually. No inbound SSH or application port is opened.

For local development, start in `platform/monitoring`, copy
`cloudflare.env.example` to `.env`, replace the placeholders, and run:

```bash
docker compose up --detach --build
```

The dashboard still shows Docker and Tunnel health when Cloudflare Analytics is
not configured; its edge section explains which configuration is missing.

## Example pages

After starting the dashboard, these views render stable sample data without
calling Docker or Cloudflare:

- `https://monitor.maimons.dev/?demo=healthy` shows a healthy platform.
- `https://monitor.maimons.dev/?demo=incident` shows a stopped app, high worker
  utilization, reduced Tunnel connections, and elevated Tunnel errors.

Both pages display an `Example data` banner so they cannot be confused with the
live dashboard.

## Security notes

- Cloudflare Access is the authorization boundary. The app itself is read-only
  and displays the authenticated email header only as context.
- The Docker socket is never mounted into the dashboard. The socket proxy allows
  only the container, engine-info, and ping GET endpoints; write requests are
  disabled.
- The cloudflared metrics listener is on host port `20241` so the local
  dashboard container can read it. Do not add that port to the EC2 security
  group.
- No dashboard data or credentials are stored by the app. The API token is read
  at deployment time from AWS Secrets Manager and written to a root-only
  environment file on the host.
