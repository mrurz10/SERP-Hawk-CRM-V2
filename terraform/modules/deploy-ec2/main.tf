# ---------------------------------------------------------------------------
# Auto-discover default VPC and a public subnet within it
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

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
  name = "${var.name_prefix}-deploy-ec2-role"

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

  tags = var.tags
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

# Optional: lets the instance read app secrets from SSM Parameter Store
# at /<name_prefix>/* (e.g. /serp-hawk/database_url)
resource "aws_iam_role_policy" "ssm_parameter_read" {
  count = var.enable_ssm_secrets_access ? 1 : 0

  name = "${var.name_prefix}-app-secrets-read"
  role = aws_iam_role.deploy_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/${var.name_prefix}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "deploy_ec2_profile" {
  name = "${var.name_prefix}-deploy-ec2-profile"
  role = aws_iam_role.deploy_ec2_role.name
}

# ---------------------------------------------------------------------------
# Security Group — only inbound app ports; SSM needs no inbound rules at all
# ---------------------------------------------------------------------------
resource "aws_security_group" "deploy_sg" {
  name        = "${var.name_prefix}-deploy-sg"
  description = "Security group for ${var.name_prefix} deployment EC2"
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

  tags = merge(var.tags, { Name = "${var.name_prefix}-deploy-sg" })
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
# EC2 Instance — Docker, Compose & SSM Agent configured via user_data
# ---------------------------------------------------------------------------
resource "aws_instance" "deploy_server" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.deploy_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.deploy_ec2_profile.name
  key_name               = var.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = file("${path.module}/user_data.sh")

  tags = merge(var.tags, { Name = "${var.name_prefix}-deploy-server" })
}

# ---------------------------------------------------------------------------
# Elastic IP — static public IP attached to the deployment instance
# ---------------------------------------------------------------------------
resource "aws_eip" "deploy_eip" {
  domain   = "vpc"
  instance = aws_instance.deploy_server.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-deploy-eip" })

  depends_on = [aws_instance.deploy_server]
}
