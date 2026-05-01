output "ecr_repository_url" {
  description = "ECR repository URL for building and pushing images"
  value       = aws_ecr_repository.app.repository_url
}

output "instance_public_ips" {
  description = "Public IPs of app instances (use in Kamal deploy config)"
  value       = module.app_instance[*].public_ip
}

output "instance_public_dns" {
  description = "Public DNS names of app instances"
  value       = module.app_instance[*].public_dns
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
