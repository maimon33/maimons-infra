# Monitoring deployment root

This directory is the operational root for the infrastructure monitoring app.
Run its Docker and Terraform commands here. The Terraform entry files link to
the canonical production definitions in `environments/prod`, so both locations
use the same resources, resource addresses, and remote state. This keeps the
shared Cloudflare Tunnel configuration under one Terraform owner.

## Apply infrastructure from macOS

From this directory:

```bash
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

Fill in the backend and production variable files before initializing. They are
ignored by Git. The Cloudflare token must be able to edit Tunnel configuration,
DNS, and Access applications and policies. Use the account and zone identifiers
for `maimons.dev`.

The same apply manages the shared host and Tunnel, the monitoring ECR
repository and runtime secret container, the `monitor.maimons.dev` orange-cloud
DNS record, the `localhost:3001` Tunnel ingress, and the email-only Access
policy.

## Run locally

```bash
cp cloudflare.env.example .env
docker compose up --detach --build
```

The deployment workflow also uses this directory as its working directory. It
builds from `app`, sends `compose.yaml` and `deploy.sh` to the host, and verifies
`http://127.0.0.1:3001/healthz`.

The app stores 30 days of hourly container metric low/high rollups in the
`platform-monitoring-history` Docker volume. Current metrics and retained
low/high values are also available in Prometheus format at
`http://127.0.0.1:3001/metrics`.
