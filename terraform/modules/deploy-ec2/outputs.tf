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

output "iam_role_name" {
  description = "IAM role name attached to the deployment EC2 (useful for attaching further policies from the root module)"
  value       = aws_iam_role.deploy_ec2_role.name
}

output "security_group_id" {
  description = "Security group ID attached to the deployment EC2"
  value       = aws_security_group.deploy_sg.id
}
