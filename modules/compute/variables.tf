variable "ami_id" {
  description = "AMI ID used by the shared EC2 host; set this to the imported instance AMI."
  type        = string
}

variable "availability_zone" {
  description = "Availability Zone for the host and data volume."
  type        = string
}

variable "data_volume_device_name" {
  description = "Linux device name used for the persistent application data volume."
  type        = string
  default     = "/dev/sdf"
}

variable "data_volume_iops" {
  description = "Provisioned IOPS for the gp3 application data volume."
  type        = number
  default     = 3000
}

variable "data_volume_size" {
  description = "Size in GiB of the persistent application data volume."
  type        = number
  default     = 100
}

variable "data_volume_throughput" {
  description = "Throughput in MiB/s for the gp3 application data volume."
  type        = number
  default     = 125
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "instance_profile_name" {
  description = "IAM instance profile assigned to the shared host."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the shared host."
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Optional EC2 key pair retained for emergency access."
  type        = string
  default     = null
  nullable    = true
}

variable "kms_key_arn" {
  description = "KMS key ARN used to encrypt host EBS volumes."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "root_volume_size" {
  description = "Size in GiB of the EC2 root volume."
  type        = number
  default     = 30
}

variable "security_group_ids" {
  description = "Security group IDs assigned to the host."
  type        = list(string)
}

variable "subnet_id" {
  description = "Subnet ID for the shared host."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}

