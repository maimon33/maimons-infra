variable "aws_region" {
  description = "AWS region in which the Terraform state bucket is created."
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name used to identify the shared infrastructure project."
  type        = string
  default     = "maimons-infra"
}

variable "state_bucket_name" {
  description = "Globally unique name of the S3 bucket that stores Terraform state."
  type        = string
}

