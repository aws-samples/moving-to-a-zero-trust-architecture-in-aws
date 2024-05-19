# ---------- frontend/providers.tf ----------

variable "aws_region" {
  type        = string
  description = "AWS Region."

  default = "eu-west-1"
}

variable "client_vpn" {
  type        = map(string)
  description = "Client VPN configuration information."
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