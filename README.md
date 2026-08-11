# Maimons shared infrastructure

Terraform for the shared EC2 platform that hosts Mosar and future services behind a Cloudflare Tunnel.

Cloudflare terminates public TLS. The origin path is HTTP-only and security-group restricted to Cloudflare's published IPv4 and IPv6 ranges; application ports are never published.

## Layout

- `bootstrap/state` creates the encrypted, versioned S3 Terraform backend.
- `environments/prod` contains the canonical production Terraform definitions.
- `modules` contains import-friendly AWS and Cloudflare resource groups.
- `platform/monitoring` contains the monitoring app and its operational
  Terraform root. Its linked entry files use the canonical production
  definitions and state.
- `docs/import-guide.md` describes the safe import sequence for existing resources.
- `docs/monitoring.md` describes the protected Docker and Cloudflare monitoring dashboard.

## Safe first run

```bash
cd bootstrap/state
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

cd ../../platform/monitoring
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan -refresh-only
```

Do not run a normal `apply` against the existing host until the import guide is complete and the plan contains no unintended replacements.

Authentication is intentionally external. Use an authenticated shell with AWS credentials or SSO and `CLOUDFLARE_API_TOKEN`; no credentials belong in this repository.
