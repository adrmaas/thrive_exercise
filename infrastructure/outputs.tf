output "ecr_repository_url" {
  description = "ECR repository URL for building and pushing images"
  value       = aws_ecr_repository.app.repository_url
}

output "dashboard_url" {
  description = "CloudWatch dashboard URL"
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.app_name}"
}

output "app_url" {
  description = "URL of the deployed application"
  value       = "http://${module.app_instance.public_dns}"
}

output "instance_public_ip" {
  description = "Public IP of app instance (for reference; Kamal connects via instance ID)"
  value       = module.app_instance.public_ip
}

output "instance_public_dns" {
  description = "Public DNS of app instance"
  value       = module.app_instance.public_dns
}

output "instance_id" {
  description = "Instance ID (use for SSM Session Manager access)"
  value       = module.app_instance.id
}

output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnets
}

output "private_subnet_ids" {
  description = "Private subnet IDs (for future RDS, ECS, etc.)"
  value       = module.vpc.private_subnets
}
