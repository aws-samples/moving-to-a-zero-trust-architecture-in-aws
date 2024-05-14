# ---------- network/variables.tf ----------

variable "aws_region" {
  type        = string
  description = "AWS Region."

  default = "eu-west-1"
}

variable "hosted_zone_name" {
  type        = string
  description = "Private Hosted Zone name."
}

variable "frontend_account" {
  type        = string
  description = "Frontend Account ID."
}

variable "backend_account" {
  type        = string
  description = "Backend Account ID."
}

