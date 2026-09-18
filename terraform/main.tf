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

# ---------------------------------------------------------------------------
# Variables
# ---------------------------------------------------------------------------
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for the deployment server"
  type        = string
  default     = "t3.medium"
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

# ---------------------------------------------------------------------------
# Auto-discover default VPC and a public subnet within it
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

# Picks the first subnet in the default VPC that auto-assigns public IPs
data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }

  filter {
    name   = "default-for-az"
    values = ["true"]
  }
}

# ---------------------------------------------------------------------------
# IAM Role + Instance Profile (SSM-managed, ECR read-only)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "deploy_ec2_role" {
  name = "serp-hawk-deploy-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Lets AWS Systems Manager (SSM) manage this instance — no SSH/open ports needed
resource "aws_iam_role_policy_attachment" "ssm_managed_instance" {
  role       = aws_iam_role.deploy_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Lets the instance pull images from ECR
resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.deploy_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "deploy_ec2_profile" {
  name = "serp-hawk-deploy-ec2-profile"
  role = aws_iam_role.deploy_ec2_role.name
}

# ---------------------------------------------------------------------------
# Security Group — only inbound app ports; SSM needs no inbound rules at all
# ---------------------------------------------------------------------------
resource "aws_security_group" "deploy_sg" {
  name        = "serp-hawk-deploy-sg"
  description = "Security group for SERP Hawk CRM deployment EC2"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Backend API"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  ingress {
    description = "Frontend"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = [var.allowed_http_cidr]
  }

  # Optional: only opened if key_name is provided, for emergency fallback access
  dynamic "ingress" {
    for_each = var.key_name != null ? [1] : []
    content {
      description = "SSH (emergency fallback only)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_http_cidr]
    }
  }

  egress {
    description = "Allow all outbound (needed for ECR pulls, SSM, package installs)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "serp-hawk-deploy-sg"
  }
}

# ---------------------------------------------------------------------------
# Latest Amazon Linux 2023 AMI
# ---------------------------------------------------------------------------
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# EC2 Instance — Docker + Compose installed via user_data on first boot
# ---------------------------------------------------------------------------
resource "aws_instance" "deploy_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.deploy_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.deploy_ec2_profile.name
  key_name               = var.key_name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -e

    # Install Docker
    dnf update -y
    dnf install -y docker
    systemctl enable docker
    systemctl start docker
    usermod -aG docker ec2-user

    # Install Docker Compose plugin
    mkdir -p /usr/local/lib/docker/cli-plugins
    curl -SL https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64 \
      -o /usr/local/lib/docker/cli-plugins/docker-compose
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

    # Install AWS CLI v2
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install

    # SSM Agent is pre-installed on Amazon Linux 2023 AMIs by default
  EOF

  tags = {
    Name = "serp-hawk-deploy-server"
  }
}

# ---------------------------------------------------------------------------
# Elastic IP — static public IP attached to the deployment instance
# ---------------------------------------------------------------------------
resource "aws_eip" "deploy_eip" {
  domain   = "vpc"
  instance = aws_instance.deploy_server.id

  tags = {
    Name = "serp-hawk-deploy-eip"
  }

  depends_on = [aws_instance.deploy_server]
}

# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------
output "instance_id" {
  description = "EC2 instance ID — use this in the GitHub Actions deploy job's aws ssm send-command"
  value       = aws_instance.deploy_server.id
}

output "instance_public_ip" {
  description = "Static Elastic IP attached to the deployment server"
  value       = aws_eip.deploy_eip.public_ip
}

output "vpc_id" {
  description = "Default VPC ID used for this instance"
  value       = data.aws_vpc.default.id
}

output "subnet_id" {
  description = "Subnet ID the instance was launched into"
  value       = data.aws_subnets.public.ids[0]
}

output "iam_role_arn" {
  description = "IAM role ARN attached to the deployment EC2"
  value       = aws_iam_role.deploy_ec2_role.arn
}
