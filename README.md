# HA static website: EC2 (Paris) → ALB → CloudFront

```
Viewers (worldwide)
      │ HTTPS (HTTP/2, HTTP/3, IPv6)
      ▼
CloudFront (all edge locations) ── Origin Shield (eu-west-3)
      │ adds header  X-Origin-Verify: <secret>
      ▼
ALB (public subnets, 2+ AZs, eu-west-3)
  • SG: ingress ONLY from CloudFront managed prefix list
  • Listener default action: 403
  • Rule: forward only if X-Origin-Verify matches
      ▼
Auto Scaling Group (private subnets, 2+ AZs) – nginx on Amazon Linux 2023
  • SG: ingress ONLY from the ALB SG
  • No public IP, no SSH (SSM Session Manager), IMDSv2, encrypted EBS
```

## How direct access to the ALB is blocked (defence in depth)

| Layer | Control | Stops |
|---|---|---|
| Network | ALB security group allows only `com.amazonaws.global.cloudfront.origin-facing` | Anyone not coming from CloudFront (connection times out) |
| Application | Secret `X-Origin-Verify` header, ALB default action = 403 | Requests from *other* CloudFront distributions (an attacker can point their own distribution at your ALB, so IP filtering alone is not enough) |
| Transport | CloudFront → ALB over HTTPS (when `domain_name` is set) | Sniffing the secret header in transit |
| Instances | Private subnets, SG only from ALB | Any bypass of the ALB |

## Deploy

```bash
terraform init
terraform apply                                   # quick test, CloudFront default domain
# or, recommended for production:
terraform apply -var domain_name=www.example.com -var route53_zone_id=Z0123...
```

> Without `domain_name`, CloudFront talks to the ALB over plain HTTP (the ALB DNS
> name can't carry a valid certificate), so the secret header is sent unencrypted
> between CloudFront and the ALB. Use a domain for anything real.

CloudFront takes a few minutes to deploy.

## Test

```bash
curl -I "$(terraform output -raw website_url)"            # 200 via CloudFront
curl -m 10 -I "http://$(terraform output -raw alb_dns_name)"  # times out (SG)
```

From a CloudFront IP without the header, you would get `403 Access denied` (listener default action).

## Rotate the origin secret (zero downtime)

The ALB accepts both the `blue` and `green` secrets; CloudFront sends only the active one.

```bash
terraform apply -var active_origin_secret=green          # CloudFront switches to green
# wait until the distribution is "Deployed", then regenerate the unused one:
terraform apply -replace='random_password.origin_secret["blue"]' -var active_origin_secret=green
```

Rotate on a schedule (e.g. every 90 days) and whenever the value may have leaked.
It is stored in Terraform state, so keep state in an encrypted, access-controlled backend (S3 + KMS).

## Update the site

Edit `website/index.html` and `terraform apply`: the launch template changes and the ASG
does a rolling instance refresh. Then invalidate the cache:

```bash
aws cloudfront create-invalidation --distribution-id "$(terraform output -raw cloudfront_distribution_id)" --paths '/*'
```

## Further hardening (not included)

- AWS WAF web ACL on the distribution (managed rule groups, rate limiting).
- ALB / CloudFront access logs to S3.
- One NAT gateway per AZ (currently one, to keep cost down; it only affects outbound traffic).
- **CloudFront VPC origins**: lets the ALB be *internal* with no public exposure at all. That's an
  even stronger alternative to the prefix list + header pattern used here.
