variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for naming all resources created by this module (e.g. 'serp-hawk')"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the deployment server"
  type        = string
  default     = "t3.micro"
}

variable "allowed_http_cidr" {
  description = "CIDR block allowed to reach the app ports (3000, 8000). Restrict this in production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Optional EC2 key pair name for emergency SSH fallback access. Leave null to disable SSH entirely (SSM-only)."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB"
  type        = number
  default     = 20
}

variable "enable_ssm_secrets_access" {
  description = "If true, grants this instance's IAM role permission to read SSM Parameter Store values under /<name_prefix>/*"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags applied to all resources in this module"
  type        = map(string)
  default     = {}
}
