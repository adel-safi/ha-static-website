# AWS-managed policies
data "aws_cloudfront_cache_policy" "optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security" {
  name = "Managed-SecurityHeadersPolicy" # HSTS, X-Frame-Options, nosniff, etc.
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = "${var.project} - EC2/ALB origin in ${var.region}"
  is_ipv6_enabled = true
  http_version    = "http2and3"
  price_class     = var.cloudfront_price_class
  aliases         = local.use_custom_domain ? [var.domain_name] : []

  default_root_object = "index.html"

  origin {
    origin_id   = "alb-paris"
    domain_name = local.use_custom_domain ? local.origin_hostname : aws_lb.this.dns_name

    # The secret header that proves the request came from THIS distribution.
    custom_header {
      name  = var.origin_verify_header_name
      value = local.origin_secret
    }

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = local.use_custom_domain ? "https-only" : "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_keepalive_timeout = 5
      origin_read_timeout      = 30
    }

    # Extra caching layer in front of the origin region: fewer requests to
    # Paris and better hit ratio worldwide.
    origin_shield {
      enabled              = true
      origin_shield_region = var.region
    }

    connection_attempts = 3
    connection_timeout  = 10
  }

  default_cache_behavior {
    target_origin_id       = "alb-paris"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id            = data.aws_cloudfront_cache_policy.optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security.id
  }

  # Keep serving cached content for a short while if the origin is failing.
  custom_error_response {
    error_code            = 502
    error_caching_min_ttl = 10
  }
  custom_error_response {
    error_code            = 503
    error_caching_min_ttl = 10
  }
  custom_error_response {
    error_code            = 504
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = !local.use_custom_domain
    acm_certificate_arn            = local.use_custom_domain ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : null
    ssl_support_method             = local.use_custom_domain ? "sni-only" : null
    minimum_protocol_version       = local.use_custom_domain ? "TLSv1.2_2021" : "TLSv1"
  }
}
