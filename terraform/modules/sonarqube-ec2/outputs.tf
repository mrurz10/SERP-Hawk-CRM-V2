output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.sonarqube_server.id
}

output "instance_public_ip" {
  description = "Static Elastic IP attached to the SonarQube server"
  value       = aws_eip.sonarqube_eip.public_ip
}

output "url" {
  description = "SonarQube dashboard URL"
  value       = "http://${aws_eip.sonarqube_eip.public_ip}"
}

output "iam_role_arn" {
  value = aws_iam_role.sonarqube_ec2_role.arn
}

output "security_group_id" {
  value = aws_security_group.sonarqube_sg.id
}
