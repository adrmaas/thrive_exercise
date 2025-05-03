resource "aws_s3_bucket" "default" {
  bucket = "hr-resume-review-exercise-terraform-state"
  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name                  = "hr-resume-review-exercise-terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "default" {
  bucket = aws_s3_bucket.default.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "default" {
  bucket = aws_s3_bucket.default.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
