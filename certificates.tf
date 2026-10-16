# Only created when domain_name + route53_zone_id are set.

locals {
  use_custom_domain = var.domain_name != "" && var.route53_zone_id != ""
  origin_hostname   = local.use_custom_domain ? "origin.${var.domain_name}" : ""
  origin_port       = local.use_custom_domain ? 443 : 80
}

# --- Viewer certificate for CloudFront (must be us-east-1) ------------------
resource "aws_acm_certificate" "cloudfront" {
  count    = local.use_custom_domain ? 1 : 0
  provider = aws.us_east_1

  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

# --- Origin certificate for the ALB (Paris) --------------------------------
resource "aws_acm_certificate" "alb" {
  count = local.use_custom_domain ? 1 : 0

  domain_name       = local.origin_hostname
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  # Keys are static (known at plan time); each cert covers a single name.
  cert_validation_options = local.use_custom_domain ? {
    (var.domain_name)       = one(aws_acm_certificate.cloudfront[0].domain_validation_options)
    (local.origin_hostname) = one(aws_acm_certificate.alb[0].domain_validation_options)
  } : {}
}

resource "aws_route53_record" "cert_validation" {
  for_each = local.cert_validation_options

  zone_id         = var.route53_zone_id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count    = local.use_custom_domain ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[var.domain_name].fqdn]
}

resource "aws_acm_certificate_validation" "alb" {
  count = local.use_custom_domain ? 1 : 0

  certificate_arn         = aws_acm_certificate.alb[0].arn
  validation_record_fqdns = [aws_route53_record.cert_validation[local.origin_hostname].fqdn]
}

# --- DNS ------------------------------------------------------------------
# origin.<domain> -> ALB (CloudFront connects here over TLS)
resource "aws_route53_record" "origin" {
  count = local.use_custom_domain ? 1 : 0

  zone_id = var.route53_zone_id
  name    = local.origin_hostname
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}

# <domain> -> CloudFront (IPv4 + IPv6)
resource "aws_route53_record" "site" {
  for_each = local.use_custom_domain ? toset(["A", "AAAA"]) : toset([])

  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = each.value

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
