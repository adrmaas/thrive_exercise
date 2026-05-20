variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "aws_account_id" {
  type    = string
}

variable "app_name" {
  type    = string
  default = "thrive-exercise"
}

variable "alert_email" {
  type        = string
  description = "Email address for CloudWatch alarm notifications"
}
