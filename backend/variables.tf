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