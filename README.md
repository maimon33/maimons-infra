# Maimons shared infrastructure

Terraform for the shared EC2 platform that hosts Mosar and future services behind Cloudflare and Traefik.

Cloudflare terminates public TLS. The origin path is HTTP-only and security-group restricted to Cloudflare's published IPv4 and IPv6 ranges; application ports are never published.

## Layout

- `bootstrap/state` creates the encrypted, versioned S3 Terraform backend.
- `environments/prod` composes the production platform and is the import target.
- `modules` contains import-friendly AWS and Cloudflare resource groups.
- `platform` contains the centrally owned Traefik runtime configuration.
- `docs/import-guide.md` describes the safe import sequence for existing resources.

## Safe first run

```bash
cd bootstrap/state
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform apply

cd ../../environments/prod
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl
terraform plan -refresh-only
```

Do not run a normal `apply` against the existing host until the import guide is complete and the plan contains no unintended replacements.

Authentication is intentionally external. Use an authenticated shell with AWS credentials or SSO and `CLOUDFLARE_API_TOKEN`; no credentials belong in this repository.
