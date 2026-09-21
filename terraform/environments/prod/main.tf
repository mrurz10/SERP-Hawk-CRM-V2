terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    # Bucket, key, region, dynamodb_table are supplied at `terraform init` time
    # via -backend-config flags in the CI workflow, so this stays portable
    # and doesn't hardcode an account-specific bucket name here.
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

module "deploy_ec2" {
  source = "../../modules/deploy-ec2"

  aws_region                = var.aws_region
  name_prefix                = var.name_prefix
  instance_type               = var.instance_type
  allowed_http_cidr           = var.allowed_http_cidr
  key_name                    = var.key_name
  enable_ssm_secrets_access   = var.enable_ssm_secrets_access

  tags = {
    Environment = "prod"
    Project     = var.name_prefix
    ManagedBy   = "terraform"
  }
}
