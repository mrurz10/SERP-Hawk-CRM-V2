terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Bucket, key, region, dynamodb_table are supplied at `terraform init` time
    # via -backend-config flags in the CI workflow.
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

module "sonarqube_ec2" {
  source = "../../modules/sonarqube-ec2"

  aws_region             = var.aws_region
  name_prefix             = var.name_prefix
  instance_type            = var.instance_type
  allowed_web_cidr         = var.allowed_web_cidr
  allowed_ssh_cidr         = var.allowed_ssh_cidr
  key_name                 = var.key_name
  sonarqube_version        = var.sonarqube_version
  db_password_ssm_param    = var.db_password_ssm_param

  tags = {
    Environment = "sonarqube"
    Project     = var.name_prefix
    ManagedBy   = "terraform"
  }
}
