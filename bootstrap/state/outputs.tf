output "backend_configuration" {
  description = "Values to copy into environments/prod/backend.hcl."
  value = {
    bucket       = aws_s3_bucket.terraform_state.id
    encrypt      = true
    key          = "platform/prod/terraform.tfstate"
    kms_key_id   = aws_kms_key.terraform_state.arn
    region       = var.aws_region
    use_lockfile = true
  }
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for Terraform state."
  value       = aws_kms_key.terraform_state.arn
}

output "state_bucket_name" {
  description = "Name of the Terraform state bucket."
  value       = aws_s3_bucket.terraform_state.id
}

