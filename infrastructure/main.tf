terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.86.1"
    }
  }
}
terraform {
  backend "s3" {
    encrypt        = true
    bucket         = "hr-resume-review-exercise-terraform-state"
    region         = "us-east-1"
    key            = "terraform.tfstate"
    use_lockfile   = true
  }
}

provider "aws" {
  alias      = "us-east-1"
  region     = "us-east-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"]
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "pr_review_profile"
  role = aws_iam_role.role.name
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "role" {
  name               = "pr_review_role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

resource "aws_instance" "app_server" {
  ami                  = data.aws_ami.ubuntu.id
  instance_type        = "t2.medium"
  key_name             = "ssh_key"
  iam_instance_profile = aws_iam_instance_profile.instance_profile.name
  tags = {
    Name = "pr_review_exercise"
  }
  root_block_device {
    volume_size           = "20"
    volume_type           = "gp3"
    iops                  = "8000"
    encrypted             = false
    delete_on_termination = true
  }
}

resource "aws_network_interface_sg_attachment" "sg_attachment" {
  security_group_id    = var.security_group_id
  network_interface_id = aws_instance.app_server.primary_network_interface_id
}