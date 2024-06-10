# ---------- frontend/providers.tf ----------

variable "aws_region" {
  type        = string
  description = "AWS Region."
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN."
}

variable "networking_account" {
  type        = string
  description = "Networking Account ID."
}

variable "frontend_domain_name" {
  type        = string
  description = "Frontend Application domain name."
}

variable "idc_group_id" {
  type        = string
  description = "Identity Center Group ID (for AWS Verified Access policy)."
}