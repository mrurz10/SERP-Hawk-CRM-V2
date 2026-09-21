output "instance_id" {
  value = module.sonarqube_ec2.instance_id
}

output "instance_public_ip" {
  value = module.sonarqube_ec2.instance_public_ip
}

output "url" {
  description = "Open this in your browser once apply finishes and the instance has booted (~5-10 min)"
  value       = module.sonarqube_ec2.url
}

output "iam_role_arn" {
  value = module.sonarqube_ec2.iam_role_arn
}
