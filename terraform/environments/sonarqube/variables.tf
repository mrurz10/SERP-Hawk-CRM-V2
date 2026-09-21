variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for naming all resources"
  type        = string
  default     = "sonarqube"
}

variable "instance_type" {
  description = "EC2 instance type - keep at t3.medium or larger, SonarQube's Elasticsearch component needs real memory"
  type        = string
  default     = "t3.medium"
}

variable "allowed_web_cidr" {
  description = "CIDR allowed to reach the SonarQube web UI. Restrict this to your office/VPN/CI runner IPs in real production - 0.0.0.0/0 exposes the dashboard to the whole internet."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH in, only relevant if key_name is set"
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access"
  type        = string
  default     = null
}

variable "sonarqube_version" {
  description = "SonarQube Community Edition version"
  type        = string
  default     = "10.6.0.92116"
}

variable "db_password_ssm_param" {
  description = "SSM SecureString parameter name holding the SonarQube DB password. Create it BEFORE running terraform apply: aws ssm put-parameter --name /sonarqube/db_password --type SecureString --value 'YourStrongPassword'"
  type        = string
  default     = "/sonarqube/db_password"
}
