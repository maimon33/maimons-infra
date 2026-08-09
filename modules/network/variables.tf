variable "availability_zone" {
  description = "Availability Zone for the shared host subnet."
  type        = string
}

variable "cloudflare_ipv4_cidrs" {
  description = "Cloudflare IPv4 ranges permitted to reach direct origin ingress."
  type        = set(string)
  default     = []
}

variable "cloudflare_ipv6_cidrs" {
  description = "Cloudflare IPv6 ranges permitted to reach direct origin ingress."
  type        = set(string)
  default     = []
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "ssh_ipv4_cidrs" {
  description = "Temporary IPv4 CIDRs permitted to use SSH; leave empty when using SSM."
  type        = set(string)
  default     = []
}

variable "subnet_cidr" {
  description = "IPv4 CIDR for the public subnet containing the shared host."
  type        = string
  default     = "10.33.1.0/24"
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the platform VPC."
  type        = string
  default     = "10.33.0.0/16"
}
