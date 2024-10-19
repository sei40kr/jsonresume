terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.40.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5.1"
    }
  }

  backend "s3" {
    bucket = "jsonresume-tfstate"
    region = "us-east-1"
    key    = "jsonresume.tfstate"
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

  statement {
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.resume.arn]
  }
}

data "aws_route53_zone" "zone" {
  name = "yong-ju.me"
}

resource "aws_acm_certificate" "resume" {
  domain_name       = "jsonresume.yong-ju.me"
  validation_method = "DNS"
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.resume.domain_validation_options : dvo.domain_name => dvo
  }

  zone_id = data.aws_route53_zone.zone.zone_id
  name    = each.value.resource_record_name
  type    = each.value.resource_record_type
  records = [each.value.resource_record_value]
  ttl     = "60"
}

resource "aws_s3_bucket" "resume" {
  bucket = "jsonresume.yong-ju.me"
}

resource "random_string" "referer" {
  length  = 32
  special = false
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

    condition {
      test     = "StringEquals"
      variable = "aws:Referer"
      values   = [random_string.referer.result]
    }
  }
}

resource "aws_s3_bucket_policy" "resume" {
  bucket = aws_s3_bucket.resume.id
  policy = data.aws_iam_policy_document.resume.json
}

resource "aws_s3_bucket_website_configuration" "resume" {
  bucket = aws_s3_bucket.resume.id

  index_document {
    suffix = "index.html"
  }
}

resource "aws_cloudfront_distribution" "resume" {
  origin {
    domain_name = aws_s3_bucket.resume.bucket_regional_domain_name

    custom_header {
      name  = "Referer"
      value = random_string.referer.result
    }

    origin_id = aws_s3_bucket.resume.id
  }

  enabled         = true
  is_ipv6_enabled = true

  aliases = ["jsonresume.yong-ju.me"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = aws_s3_bucket.resume.id

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400

    response_headers_policy_id = aws_cloudfront_response_headers_policy.allow_cors.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate.resume.arn
    ssl_support_method  = "sni-only"
  }
}

resource "aws_cloudfront_response_headers_policy" "allow_cors" {
  name    = "allow-cors"
  comment = "Allow CORS from http://localhost:3000 and https://yong-ju.me"

  cors_config {
    access_control_allow_credentials = false

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET"]
    }

    access_control_allow_origins {
      items = ["http://localhost:3000", "https://yong-ju.me"]
    }

    origin_override = true
  }
}

resource "aws_route53_record" "jsonresume" {
  zone_id = data.aws_route53_zone.zone.zone_id
  name    = "jsonresume.yong-ju.me"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.resume.domain_name
    zone_id                = aws_cloudfront_distribution.resume.hosted_zone_id
    evaluate_target_health = false
  }
}
