variable "alarm_email_addresses" {
  description = "Email addresses subscribed to platform alarm notifications."
  type        = set(string)
  default     = []
}

variable "cpu_threshold_percent" {
  description = "Average CPU utilization percentage that triggers an alarm."
  type        = number
  default     = 80
}

variable "disk_device" {
  description = "Device dimension emitted by the CloudWatch Agent disk metric."
  type        = string
  default     = "nvme0n1p1"
}

variable "disk_fstype" {
  description = "Filesystem type dimension emitted by the CloudWatch Agent."
  type        = string
  default     = "ext4"
}

variable "disk_path" {
  description = "Filesystem path monitored by the CloudWatch Agent."
  type        = string
  default     = "/"
}

variable "disk_threshold_percent" {
  description = "Disk utilization percentage that triggers an alarm."
  type        = number
  default     = 80
}

variable "enable_agent_alarms" {
  description = "Whether to create memory and disk alarms for CloudWatch Agent metrics."
  type        = bool
  default     = true
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
}

variable "instance_id" {
  description = "ID of the shared EC2 instance."
  type        = string
}

variable "memory_threshold_percent" {
  description = "Memory utilization percentage that triggers an alarm."
  type        = number
  default     = 85
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
}

variable "tags" {
  description = "Additional tags applied to module resources."
  type        = map(string)
  default     = {}
}

