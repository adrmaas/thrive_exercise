# --- SSH Key Pair ---

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "app" {
  key_name   = "${var.app_name}-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "aws_ssm_parameter" "ssh_private_key" {
  name  = "/${var.app_name}/SSH_PRIVATE_KEY"
  type  = "SecureString"
  value = tls_private_key.ssh.private_key_pem
}

# --- ECR ---

resource "aws_ecr_repository" "app" {
  name                 = var.app_name
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# --- AMI ---

data "aws_ami" "ecs_optimized" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-ecs-hvm-*-x86_64"]
  }
}

# --- IAM ---

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app" {
  name               = "${var.app_name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ecr" {
  name = "ecr-pull"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:GetAuthorizationToken",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "ssm" {
  name = "ssm-read"
  role = aws_iam_role.app.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:${var.aws_region}:${var.aws_account_id}:parameter/${var.app_name}/*"
    }]
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.app_name}-profile"
  role = aws_iam_role.app.name
}

# --- Security Group ---

module "app_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "5.2.0"

  name        = "${var.app_name}-sg"
  description = "Allow HTTP and HTTPS inbound; all outbound"
  vpc_id      = module.vpc.vpc_id

  ingress_rules       = ["http-80-tcp", "https-443-tcp"]
  ingress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules        = ["all-all"]
}

# --- EC2 Instance ---

module "app_instance" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  version = "5.7.1"

  name                        = var.app_name
  ami                         = data.aws_ami.ecs_optimized.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.app.key_name
  iam_instance_profile        = aws_iam_instance_profile.app.name
  vpc_security_group_ids      = [module.app_sg.security_group_id]
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  root_block_device = [{
    volume_size           = 30
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }]
}

# --- CloudWatch Agent SSM Association ---

resource "aws_ssm_association" "cloudwatch_agent" {
  name = "AWS-ConfigureAWSPackage"

  parameters = {
    action = "Install"
    name   = "AmazonCloudWatchAgent"
  }

  targets {
    key    = "tag:Name"
    values = [var.app_name]
  }
}

resource "aws_ssm_association" "cloudwatch_agent_config" {
  name = "AmazonCloudWatch-ManageAgent"

  parameters = {
    action                        = "configure"
    optionalConfigurationSource   = "ssm"
    optionalConfigurationLocation = aws_ssm_parameter.cloudwatch_agent_config.name
    optionalRestart               = "yes"
  }

  targets {
    key    = "tag:Name"
    values = [var.app_name]
  }

  depends_on = [aws_ssm_association.cloudwatch_agent]
}

resource "aws_ssm_parameter" "cloudwatch_agent_config" {
  name  = "/${var.app_name}/cloudwatch-agent-config"
  type  = "String"
  value = jsonencode({
    logs = {
      logs_collected = {
        files = {
          collect_list = [{
            file_path        = "/var/lib/docker/containers/**/*-json.log"
            log_group_name   = "/app/${var.app_name}"
            log_stream_name  = "{instance_id}"
            timestamp_format = "%Y-%m-%dT%H:%M:%S"
          }]
        }
      }
    }
    metrics = {
      metrics_collected = {
        mem  = { measurement = ["mem_used_percent"] }
        disk = { measurement = ["used_percent"], resources = ["/"] }
      }
      append_dimensions = {
        InstanceId = "$${aws:InstanceId}"
      }
    }
  })
}

# --- SSM Parameters (app secrets) ---

resource "random_password" "secret_key_base" {
  length  = 128
  special = false
}

resource "aws_ssm_parameter" "secret_key_base" {
  name  = "/${var.app_name}/SECRET_KEY_BASE"
  type  = "SecureString"
  value = random_password.secret_key_base.result
}

resource "random_password" "username" {
  length  = 16
  special = false
}

resource "random_password" "password" {
  length  = 32
  special = true
}

resource "aws_ssm_parameter" "username" {
  name  = "/${var.app_name}/USERNAME"
  type  = "SecureString"
  value = random_password.username.result
}

resource "aws_ssm_parameter" "password" {
  name  = "/${var.app_name}/PASSWORD"
  type  = "SecureString"
  value = random_password.password.result
}

# --- CloudWatch ---

resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/${var.app_name}"
  retention_in_days = 7
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.app_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU above 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = module.app_instance.id
  }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "${var.app_name}-status-check"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "EC2 status check failed"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = module.app_instance.id
  }
}

# --- SNS ---

resource "aws_sns_topic" "alerts" {
  name = "${var.app_name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Deploy handoff (read by deploy workflow) ---

resource "aws_ssm_parameter" "ecr_url" {
  name  = "/${var.app_name}/deploy/ECR_URL"
  type  = "String"
  value = aws_ecr_repository.app.repository_url
}

resource "aws_ssm_parameter" "instance_id" {
  name  = "/${var.app_name}/deploy/INSTANCE_ID"
  type  = "String"
  value = module.app_instance.id
}
