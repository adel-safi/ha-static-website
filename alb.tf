resource "aws_lb" "this" {
  name               = "${var.project}-alb"
  load_balancer_type = "application"
  internal           = false
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  drop_invalid_header_fields = true
  desync_mitigation_mode     = "strictest"
}

resource "aws_lb_target_group" "web" {
  name     = "${var.project}-web"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.this.id

  deregistration_delay = 30

  health_check {
    path                = "/health"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# The listener's DEFAULT action rejects everything. Only requests that carry
# the secret header set by CloudFront are forwarded to the instances.
resource "aws_lb_listener" "origin" {
  load_balancer_arn = aws_lb.this.arn
  port              = local.origin_port
  protocol          = local.use_custom_domain ? "HTTPS" : "HTTP"
  ssl_policy        = local.use_custom_domain ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : null
  certificate_arn   = local.use_custom_domain ? aws_acm_certificate_validation.alb[0].certificate_arn : null

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Access denied"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "from_cloudfront" {
  listener_arn = aws_lb_listener.origin.arn
  priority     = 1

  condition {
    http_header {
      http_header_name = var.origin_verify_header_name
      # Both secrets are accepted so rotation never causes a 403 window.
      values = [for s in random_password.origin_secret : s.result]
    }
  }

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}
