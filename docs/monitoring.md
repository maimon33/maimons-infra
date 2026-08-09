# Simple platform monitoring

The platform includes a small, read-only dashboard at
`https://monitor.maimons.org`. It is one Python application with no database and
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
  `http://localhost:3000`;
- a Cloudflare Access application covering the complete hostname;
- an allow policy containing only the configured operator email addresses.

The dashboard publishes port 3000 only on host loopback, so cloudflared can
reach it but remote clients cannot bypass Cloudflare Access. The supporting
Docker API proxy exists only on the internal `platform-monitoring` network.

## Configure and run

1. Create a dedicated Cloudflare API token with `Zone Analytics Read` for the
   selected zone. Do not reuse the Tunnel management token.
2. Copy `platform/monitoring/cloudflare.env.example` to `platform/.env`, replace
   every placeholder, and keep that file out of source control.
3. Set the operator allowlist in the monitoring entry in the production
   `services` value.
4. Review and apply the production Terraform plan.
5. For the existing host, run `modules/ec2-startup/cloudflared-startup.sh` once
   as root through Systems Manager. New hosts run it from user data. This step is
   required because changing EC2 user data does not rerun cloud-init on an
   existing instance.
6. On the host, place this repository under `/opt/platform` and run:

   ```bash
   docker compose --project-directory /opt/platform \
     --file /opt/platform/compose.yaml up --detach --build
   ```

The dashboard still shows Docker and Tunnel health when Cloudflare Analytics is
not configured; its edge section explains which configuration is missing.

## Example pages

After starting the dashboard, these views render stable sample data without
calling Docker or Cloudflare:

- `https://monitor.maimons.org/?demo=healthy` shows a healthy platform.
- `https://monitor.maimons.org/?demo=incident` shows a stopped app, high worker
  utilization, reduced Tunnel connections, and elevated Tunnel errors.

Both pages display an `Example data` banner so they cannot be confused with the
live dashboard.

## Security notes

- Cloudflare Access is the authorization boundary. The app itself is read-only
  and displays the authenticated email header only as context.
- The Docker socket is never mounted into the dashboard. The socket proxy allows
  only the container, engine-info, and ping GET endpoints; write requests are
  disabled.
- The cloudflared metrics listener is on host port `20241` only so the local
  dashboard container can read it. Do not add that port to the EC2 security
  group.
- No dashboard data or credentials are stored by the app. The API token is read
  from the untracked platform environment file.
