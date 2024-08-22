# ---------- frontend/variables.tf ----------

variable "aws_region" {
  type        = string
  description = "AWS Region."

  default = "eu-west-1"
}

variable "certificate_arn" {
  type        = string
  description = "ACM certificate ARN."
}

variable "networking_account" {
  type        = string
  description = "Networking Account ID."
}

variable "backend_service1_domain_name" {
  type        = string
  description = "Backend App1 - Domain Name."
}

variable "backend_service2_domain_name" {
  type        = string
  description = "Backend App2 - Domain Name."
}

variable "frontend_application_role_arn" {
  type        = string
  description = "Frontend Application Role ARN."
}