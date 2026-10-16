output "website_url" {
  description = "Public URL (CloudFront)."
  value       = local.use_custom_domain ? "https://${var.domain_name}" : "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "alb_dns_name" {
  description = "Direct ALB hostname - should time out / return 403 when hit directly."
  value       = aws_lb.this.dns_name
}

output "origin_verify_header_value" {
  description = "Active secret header value (for debugging only)."
  value       = local.origin_secret
  sensitive   = true
}
