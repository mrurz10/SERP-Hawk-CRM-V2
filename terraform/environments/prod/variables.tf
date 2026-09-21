variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for naming all resources (e.g. 'serp-hawk')"
  type        = string
  default     = "serp-hawk"
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

variable "enable_ssm_secrets_access" {
  description = "If true, grants the deploy EC2 permission to read app secrets from SSM Parameter Store"
  type        = bool
  default     = true
}
