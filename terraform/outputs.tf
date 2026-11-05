
output "ec2_public_ip" {
  description = "Public IP of application EC2"
  value       = aws_instance.application.public_ip
}

output "ec2_instance_id" {
  value = aws_instance.application.id
}

output "ecr_repositories" {
  value = {
    for name, repo in aws_ecr_repository.services :
    name => repo.repository_url
  }
}

output "aws_region" {
  value = var.aws_region
}
