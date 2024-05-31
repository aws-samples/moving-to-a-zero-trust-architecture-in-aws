# ---------- backend/providers.tf ----------

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "= 0.78.0"
    }
  }

  backend "s3" {
    bucket         = "nis343-backend-tfstate"
    key            = "backend"
    region         = "eu-west-1"
    dynamodb_table = "nis343-backend-tfstate"
  }
}

provider "aws" {
  region = var.aws_region
}

provider "awscc" {
  region = var.aws_region
}