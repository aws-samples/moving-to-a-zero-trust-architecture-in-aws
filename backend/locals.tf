# ---------- frontend/locals.tf ----------

locals {
  service1_policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow"
        "Principal" : {
          "AWS" : "${var.frontend_application_role_arn}"
        }
        "Action" : "vpc-lattice-svcs:Invoke"
        "Resource" : "${module.vpclattice_service1.services.mservice1.attributes.arn}/secure*"
      },
      {
        "Effect" : "Allow"
        "Principal" : "*"
        "Action" : "vpc-lattice-svcs:Invoke"
        "Resource" : "${module.vpclattice_service1.services.mservice1.attributes.arn}/*"
      },
      {
        "Effect" : "Deny"
        "Principal" : "*"
        "Action" : "vpc-lattice-svcs:Invoke"
        "Resource" : "${module.vpclattice_service1.services.mservice1.attributes.arn}/secure*"
        "Condition" : {
          "StringEquals" : {
            "aws:PrincipalType" : "Anonymous"
          }
        }
      }
    ]
  })

  service2_policy = jsonencode({
    "Version" : "2012-10-17"
    "Statement" : [
      {
        "Effect" : "Allow"
        "Principal" : {
          "AWS" : "arn:aws:iam::992382807606:role/mservice1"
        }
        "Action" : "vpc-lattice-svcs:Invoke"
        "Resource" : "${module.vpclattice_service2.services.mservice2.attributes.arn}/secure*"
      },
      {
        "Effect" : "Allow"
        "Principal" : "*"
        "Action" : "vpc-lattice-svcs:Invoke"
        "Resource" : "${module.vpclattice_service2.services.mservice2.attributes.arn}/*"
      },
      {
        "Effect" : "Deny"
        "Principal" : "*"
        "Action" : "vpc-lattice-svcs:Invoke"
        "Resource" : "${module.vpclattice_service2.services.mservice2.attributes.arn}/secure*"
        "Condition" : {
          "StringEquals" : {
            "aws:PrincipalType" : "Anonymous"
          }
        }
      }
    ]
  })
}