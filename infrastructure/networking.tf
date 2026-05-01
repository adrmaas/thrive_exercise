module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.19.0"

  name = "${var.app_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]
  private_subnets = ["10.0.11.0/24", "10.0.12.0/24"]

  enable_nat_gateway = false
  enable_vpn_gateway = false

  # Tag subnets for future ALB/ECS use
  public_subnet_tags = {
    Tier = "public"
  }

  private_subnet_tags = {
    Tier = "private"
  }
}
