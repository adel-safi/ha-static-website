# ---------------------------------------------------------------------------
# Layer 1 (network): the ALB only accepts traffic from CloudFront's
# origin-facing IP ranges, via the AWS-managed prefix list (kept up to date
# by AWS). Note: this prefix list counts as ~55 rules toward the SG quota.
# ---------------------------------------------------------------------------
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

resource "aws_security_group" "alb" {
  name        = "${var.project}-alb"
  description = "ALB - ingress from CloudFront origin-facing IPs only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_from_cloudfront" {
  security_group_id = aws_security_group.alb.id
  description       = "CloudFront origin-facing only"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = local.origin_port
  to_port           = local.origin_port
}

resource "aws_vpc_security_group_egress_rule" "alb_to_web" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To web servers"
  referenced_security_group_id = aws_security_group.web.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

# Web servers: only reachable from the ALB. No SSH - use SSM Session Manager.
resource "aws_security_group" "web" {
  name        = "${var.project}-web"
  description = "Web servers - ingress from ALB only"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.project}-web" }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from ALB"
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
}

resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS out (dnf repos, SSM) via NAT"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# ---------------------------------------------------------------------------
# Layer 2 (application): a secret header that only CloudFront knows.
# The prefix list alone is not enough - it matches *any* CloudFront
# distribution, including one an attacker creates. Two secrets exist so they
# can be rotated without downtime (ALB accepts both, CloudFront sends one).
# ---------------------------------------------------------------------------
resource "random_password" "origin_secret" {
  for_each = toset(["blue", "green"])

  length  = 48
  special = false
}

locals {
  origin_secret = random_password.origin_secret[var.active_origin_secret].result
}
