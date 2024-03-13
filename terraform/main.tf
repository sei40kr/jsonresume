terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.67.0"
    }
  }

  backend "s3" {
    bucket = "jsonresume-tfstate"
    region = "us-east-1"
    key = "jsonresume.tfstate"
  }
}

provider "aws" {
  region  = "us-east-1"
  profile = "jsonresume"

  default_tags {
    tags = {
      Project = "jsonresume"
    }
  }
}

resource "aws_budgets_budget" "ci" {
  name              = "jsonresume"
  budget_type       = "COST"
  limit_amount      = "1"
  limit_unit        = "USD"
  time_period_start = "2023-05-21_00:00"
  time_unit         = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["Project$jsonresume"]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = ["sei40kr@gmail.com"]
  }
}

resource "aws_iam_access_key" "ci" {
  user = aws_iam_user.ci.name
}

resource "aws_iam_policy" "ci" {
  name   = "jsonresume-ci"
  policy = data.aws_iam_policy_document.ci.json
}

resource "aws_iam_user" "ci" {
  name = "jsonresume-ci"
}

resource "aws_iam_user_policy_attachment" "ci" {
  user       = aws_iam_user.ci.name
  policy_arn = aws_iam_policy.ci.arn
}

data "aws_iam_policy_document" "ci" {
  statement {
    actions = [
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:PutObjectAcl",
    ]

    resources = [
      aws_s3_bucket.resume.arn,
      "${aws_s3_bucket.resume.arn}/*"
    ]
  }
}

data "aws_iam_policy_document" "resume" {
  statement {
    sid       = "PublicReadGetObject"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.resume.arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
  }
}

data "aws_route53_zone" "zone" {
  name = "yong-ju.me"
}

resource "aws_route53_record" "jsonresume" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "jsonresume.yong-ju.me"
  type    = "CNAME"
  ttl     = "300"
  records = [aws_s3_bucket_website_configuration.resume.website_domain]
}

resource "aws_s3_bucket" "resume" {
  bucket = "jsonresume.yong-ju.me"
}

resource "aws_s3_bucket_cors_configuration" "resume" {
  bucket = aws_s3_bucket.resume.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET"]
    allowed_origins = ["https://yong-ju.me", "http://localhost:3000"]
    expose_headers  = ["ETag"]
  }
}

resource "aws_s3_bucket_policy" "resume" {
  bucket = aws_s3_bucket.resume.id
  policy = data.aws_iam_policy_document.resume.json
}

resource "aws_s3_bucket_public_access_block" "example" {
  bucket = aws_s3_bucket.resume.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "resume" {
  bucket = aws_s3_bucket.resume.id

  index_document {
    suffix = "index.html"
  }
}
