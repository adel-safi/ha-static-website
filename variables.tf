variable "project" {
  description = "Name prefix for all resources."
  type        = string
  default     = "ha-static-website"
}

variable "region" {
  description = "Origin region (Paris)."
  type        = string
  default     = "eu-west-3"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of Availability Zones to spread the ALB and instances across."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3 (ALB needs at least 2 AZs; eu-west-3 has 3)."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web servers."
  type        = string
  default     = "t3.micro"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "origin_verify_header_name" {
  description = "Name of the secret header CloudFront adds to every origin request."
  type        = string
  default     = "X-Origin-Verify"
}

variable "active_origin_secret" {
  description = <<-EOT
    Which of the two origin secrets ("blue" or "green") CloudFront currently sends.
    The ALB accepts both, which allows zero-downtime rotation (see README).
  EOT
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "green"], var.active_origin_secret)
    error_message = "active_origin_secret must be \"blue\" or \"green\"."
  }
}

variable "domain_name" {
  description = <<-EOT
    Optional. Public hostname for the site (e.g. www.example.com). When set together with
    route53_zone_id, the stack issues ACM certificates, serves viewers on this name and,
    importantly, encrypts CloudFront -> ALB traffic with HTTPS so the secret header never
    travels in clear text. Strongly recommended for production.
  EOT
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Optional. Public Route 53 hosted zone ID that contains domain_name."
  type        = string
  default     = ""
}

variable "cloudfront_price_class" {
  description = "PriceClass_All = every edge location worldwide."
  type        = string
  default     = "PriceClass_All"
}
