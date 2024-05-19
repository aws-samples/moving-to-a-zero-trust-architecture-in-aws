# ---------- modules/retreive_parameters/main.tf ----------

# Obtain AWS Region
data "aws_region" "current" {}

# Retrieving parameters
data "aws_ssm_parameter" "parameter" {
  for_each = var.parameters

  name = "arn:aws:ssm:${data.aws_region.current.name}:${each.value}:parameter/${each.key}"
}