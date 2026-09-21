variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
}

variable "name_prefix" {
  description = "Prefix used for naming all resources created by this module (e.g. 'sonarqube')"
  type        = string
  default     = "sonarqube"
}

variable "instance_type" {
  description = "EC2 instance type. SonarQube's Elasticsearch component needs real memory - do not use anything below t3.medium (4GB RAM), or SonarQube will crash-loop."
  type        = string
  default     = "t3.medium"
}

variable "allowed_web_cidr" {
  description = "CIDR block allowed to reach SonarQube's web UI (port 80, proxied to 9000). Restrict this to your office/VPN/CI runner IPs in real production."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH in, only used if key_name is set."
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "Optional EC2 key pair name for SSH access. Leave null to disable SSH entirely."
  type        = string
  default     = null
}

variable "root_volume_size" {
  description = "Root EBS volume size in GB. SonarQube + Postgres + Elasticsearch data grows over time - 30GB+ recommended."
  type        = number
  default     = 30
}

variable "sonarqube_version" {
  description = "SonarQube Community Edition version to install"
  type        = string
  default     = "10.6.0.92116"
}

variable "db_name" {
  description = "PostgreSQL database name for SonarQube"
  type        = string
  default     = "sonarqube"
}

variable "db_user" {
  description = "PostgreSQL username for SonarQube"
  type        = string
  default     = "sonar"
}

variable "db_password_ssm_param" {
  description = "Name of the SSM SecureString parameter holding the SonarQube database password. Must already exist (create it manually via `aws ssm put-parameter` before applying) — never pass the raw password as a Terraform variable, since that would land in state in plaintext."
  type        = string
}

variable "tags" {
  description = "Extra tags applied to all resources in this module"
  type        = map(string)
  default     = {}
}
