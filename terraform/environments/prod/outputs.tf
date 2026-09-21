output "instance_id" {
  description = "EC2 instance ID — use this in the GitHub Actions deploy job's aws ssm send-command"
  value       = module.deploy_ec2.instance_id
}

output "instance_public_ip" {
  description = "Static Elastic IP attached to the deployment server"
  value       = module.deploy_ec2.instance_public_ip
}

output "vpc_id" {
  value = module.deploy_ec2.vpc_id
}

output "subnet_id" {
  value = module.deploy_ec2.subnet_id
}

output "iam_role_arn" {
  value = module.deploy_ec2.iam_role_arn
}

output "security_group_id" {
  value = module.deploy_ec2.security_group_id
}
