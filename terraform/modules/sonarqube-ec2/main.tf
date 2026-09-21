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
# IAM Role + Instance Profile
# Grants permission to read ONLY the one SSM parameter holding the DB
# password - not broad SSM access, and no long-lived credentials on disk.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "sonarqube_ec2_role" {
  name = "${var.name_prefix}-ec2-role"

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

resource "aws_iam_role_policy" "ssm_db_password_read" {
  name = "${var.name_prefix}-db-password-read"
  role = aws_iam_role.sonarqube_ec2_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:aws:ssm:${var.aws_region}:*:parameter${var.db_password_ssm_param}"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "sonarqube_ec2_profile" {
  name = "${var.name_prefix}-ec2-profile"
  role = aws_iam_role.sonarqube_ec2_role.name
}

# ---------------------------------------------------------------------------
# Security Group
# Port 80 (Nginx -> SonarQube 9000) exposed per allowed_web_cidr.
# Port 9000 is intentionally NOT opened externally - only Nginx on
# localhost talks to it; keeps SonarQube itself off the public internet.
# ---------------------------------------------------------------------------
resource "aws_security_group" "sonarqube_sg" {
  name        = "${var.name_prefix}-sg"
  description = "Security group for ${var.name_prefix} EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Web UI (via Nginx reverse proxy)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.allowed_web_cidr]
  }

  dynamic "ingress" {
    for_each = var.key_name != null ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.allowed_ssh_cidr]
    }
  }

  egress {
    description = "Allow all outbound (needed for package installs, SSM, downloads)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-sg" })
}

# ---------------------------------------------------------------------------
# Latest Ubuntu 22.04 LTS AMI
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu_22_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# EC2 Instance — Java, PostgreSQL, SonarQube, Nginx configured via user_data
# ---------------------------------------------------------------------------
resource "aws_instance" "sonarqube_server" {
  ami                    = data.aws_ami.ubuntu_22_04.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.public.ids[0]
  vpc_security_group_ids = [aws_security_group.sonarqube_sg.id]
  iam_instance_profile   = aws_iam_instance_profile.sonarqube_ec2_profile.name
  key_name               = var.key_name

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  user_data = templatefile("${path.module}/user_data.sh.tpl", {
    sonarqube_version   = var.sonarqube_version
    db_name             = var.db_name
    db_user             = var.db_user
    db_password_ssm_param = var.db_password_ssm_param
    aws_region          = var.aws_region
  })

  tags = merge(var.tags, { Name = "${var.name_prefix}-server" })
}

# ---------------------------------------------------------------------------
# Elastic IP — static public IP so the URL never changes on stop/start
# ---------------------------------------------------------------------------
resource "aws_eip" "sonarqube_eip" {
  domain   = "vpc"
  instance = aws_instance.sonarqube_server.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-eip" })

  depends_on = [aws_instance.sonarqube_server]
}
