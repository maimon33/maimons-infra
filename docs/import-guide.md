# Existing platform import guide

This guide is intentionally conservative. Import records ownership in Terraform state; it must not be used to recreate or replace the current host.

## 1. Inventory and backup

Record the current AWS account, region, instance ID, AMI, instance type, Availability Zone, VPC, subnet, route table, internet gateway, security groups and rules, Elastic IP allocation, IAM profile, root volume, application data volume, S3 buckets, DNS records, Access applications, policies, and zone settings.

Before importing:

- verify a current Mosar database backup can be restored;
- snapshot every attached EBS volume;
- rotate the exposed Grafana credential;
- confirm port 3010 is not public;
- export the current Cloudflare configuration.

## 2. Bootstrap state

Apply `bootstrap/state` using local state, then migrate the production stack to the resulting backend using `environments/prod/backend.hcl`.

The S3 backend uses native S3 lock files. No DynamoDB locking table is required.

## 3. Populate exact current values

Copy `terraform.tfvars.example` to the ignored `terraform.tfvars`. Use the current instance AMI, instance type, key pair, volume sizes, CIDRs, region, and Availability Zone. Placeholder values are not safe for import.

Set `manage_cloudflare_zone_settings = false` and `manage_cloudflare_cache_rules = false` for the first import pass. Enable them only after every hostname in the zone has been reviewed.

## 4. Initialize without changing infrastructure

```bash
terraform init -backend-config=backend.hcl
terraform validate
terraform plan -refresh-only
```

Copy `imports.tf.example` to the ignored `imports.tf` only after every ID is known. Import in this order:

1. VPC, internet gateway, subnet, route table, association;
2. security group and individual ingress/egress rules;
3. KMS keys and aliases;
4. S3 bucket and its ownership, encryption, versioning, public-access, and lifecycle resources;
5. IAM host role, policies, attachments, instance profile, and existing GitHub OIDC provider;
6. EC2 instance, Elastic IP and association;
7. EBS data volume and attachment;
8. ECR repositories and lifecycle policies;
9. monitoring, SNS, and AWS Backup resources;
10. Cloudflare DNS, Access application with inline policy, and zone settings.

After each group:

```bash
terraform plan
```

Stop if Terraform proposes replacing the EC2 instance, deleting a volume or bucket, detaching the production Elastic IP, or removing a Cloudflare Access policy.

## 5. Reconcile before apply

Adjust Terraform arguments to match reality. Do not use blanket `ignore_changes` to hide unexplained drift. The EC2 AMI is temporarily ignored because importing an older host against a current AMI would otherwise imply replacement; the instance still has `prevent_destroy`.

Some resources, especially Cloudflare Access policies, are represented differently by provider v5. Existing application-scoped policies belong inline in `cloudflare_zero_trust_access_application.site`. Verify the inline policy before importing the application.

## 6. Add new resources

Only after the imported plan is stable should Terraform create the new instance role permissions, ECR repositories, deployment roles, SSM contract, monitoring alarms, AWS Backup plan, separate data volume, or Traefik platform.

## 7. Runtime cutover

Terraform owns infrastructure, not the currently deployed image. Install the contents of `platform` under `/opt/platform`, create the external `edge` network, attach Mosar to it without host networking or published application ports, and test Traefik on temporary ports before replacing NGINX.

Use SSM for the cutover and retain NGINX until public health, uploads, long-running operations, admin Access, backups, and rollback have all been verified.
