# ---------- network/main.tf ----------

data "aws_organizations_organization" "org" {}

# ---------- AMAZON VPC LATTICE SERVICE NETWORK --------------
# module "vpclattice_service_network" {
#   source  = "aws-ia/amazon-vpc-lattice-module/aws"
#   version = "0.0.3"

#   service_network = {
#     name      = "central-service-network"
#     auth_type = "NONE"
#   }
# }

# # Sharing VPC Lattice service network with AWS Organization
# resource "aws_ram_resource_share" "vpclattice_resource_share" {
#   name                      = "VPC Lattice service network - Networking Account"
#   allow_external_principals = false
# }

# resource "aws_ram_principal_association" "vpclattice_principal_association" {
#   principal          = data.aws_organizations_organization.org.arn
#   resource_share_arn = aws_ram_resource_share.vpclattice_resource_share.arn
# }

# resource "aws_ram_resource_association" "vpclattice_sn_share" {
#   resource_arn       = module.vpclattice_service_network.service_network.arn
#   resource_share_arn = aws_ram_resource_share.vpclattice_resource_share.arn
# }

# ---------- IPAM ----------
module "ipam" {
  source  = "aws-ia/ipam/aws"
  version = "2.0.0"

  top_cidr       = ["10.0.0.0/8"]
  address_family = "ipv4"
  create_ipam    = true
  top_name       = "Organization IPAM"

  pool_configurations = {
    ireland = {
      name           = "ireland"
      description    = "Ireland (eu-west-1) Region"
      netmask_length = 9
      locale         = var.aws_region

      sub_pools = {
        frontend = {
          name                 = "frontend-account"
          netmask_length       = 10
          ram_share_principals = [data.aws_organizations_organization.org.arn]
        }
        backend = {
          name                 = "backend-account"
          netmask_length       = 10
          ram_share_principals = [data.aws_organizations_organization.org.arn]
        }
      }
    }
  }
}

# ---------- AMAZON ROUTE 53 ----------
# Private Hosted Zone
resource "aws_route53_zone" "private_hosted_zone" {
  name = var.hosted_zone_name

  vpc {
    vpc_id = module.network.central_vpcs.inspection.vpc_attributes.id
  }

  lifecycle {
    ignore_changes = [vpc]
  }

  tags = {
    Name = var.hosted_zone_name
  }
}

# Frontend record: Private Hosted zone
resource "aws_route53_record" "frontend_private" {
  zone_id = aws_route53_zone.private_hosted_zone.zone_id
  name    = var.frontend_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [module.retrieve_parameters.parameter.frontent_alb_domain_name]
}

# Frontend record: Public Hosted zone
resource "aws_route53_record" "frontend_public" {
  zone_id = var.public_hosted_zone_id
  name    = var.frontend_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [module.retrieve_parameters.parameter.frontend_ava_domain_name]
}

# Backend service1 and service2 records
resource "aws_route53_record" "service1" {
  zone_id = aws_route53_zone.private_hosted_zone.zone_id
  name    = var.backend_service1_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [module.retrieve_parameters.parameter.service1_domain_name]
}

resource "aws_route53_record" "service2" {
  zone_id = aws_route53_zone.private_hosted_zone.zone_id
  name    = var.backend_service2_domain_name
  type    = "CNAME"
  ttl     = 300
  records = [module.retrieve_parameters.parameter.service2_domain_name]
}

# VPC association authorization
resource "aws_route53_vpc_association_authorization" "vpc_association_auth" {
  for_each = nonsensitive(local.spoke_vpcs)

  zone_id = aws_route53_zone.private_hosted_zone.zone_id
  vpc_id  = each.value.vpc_id
}

# ---------- TRANSIT GATEWAY ----------
# Hub and Spoke network
module "network" {
  source  = "aws-ia/network-hubandspoke/aws"
  version = "3.2.0"

  identifier = "central-network"
  network_definition = {
    type  = "CIDR"
    value = "10.0.0.0/8"
  }

  transit_gateway_attributes = {
    name                           = "network-tgw"
    description                    = "Central Network TGW"
    auto_accept_shared_attachments = "enable"
  }

  central_vpcs = {
    inspection = {
      name            = "inspection-vpc"
      cidr_block      = "100.64.0.0/24"
      az_count        = 2
      inspection_flow = "east-west"

      aws_network_firewall = {
        name        = "ANFW-central-network"
        description = "AWS Network Firewall - Central Network"
        policy_arn  = aws_networkfirewall_firewall_policy.anfw_policy.arn
      }

      subnets = {
        endpoints       = { cidrs = ["100.64.0.0/28", "100.64.0.16/28"] }
        transit_gateway = { cidrs = ["100.64.0.64/28", "100.64.0.80/28"] }
      }
    }
  }

  spoke_vpcs = {
    number_vpcs     = length(local.spoke_vpcs)
    vpc_information = local.spoke_vpcs
  }
}

locals {
  frontend_vpc = jsondecode(module.retrieve_parameters.parameter.frontend_vpc)
  backend_vpcs = jsondecode(module.retrieve_parameters.parameter.backend_vpcs)
  spoke_vpcs   = merge({ frontend_vpc = local.frontend_vpc }, local.backend_vpcs)
}

# Sharing Transit Gateway with the AWS Organization
resource "aws_ram_resource_share" "resource_share" {
  name                      = "Transit Gateway - Networking Account"
  allow_external_principals = false
}

resource "aws_ram_principal_association" "principal_association" {
  principal          = data.aws_organizations_organization.org.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

resource "aws_ram_resource_association" "transit_gateway_share" {
  resource_arn       = module.network.transit_gateway.arn
  resource_share_arn = aws_ram_resource_share.resource_share.arn
}

# ---------- PARAMETERS ----------
# Sharing
module "share_parameter_share" {
  source = "../modules/share_parameter"

  parameters = {
    transit_gateway     = module.network.transit_gateway.id
    ipam_frontend       = module.ipam.pools_level_2["ireland/frontend"].id
    ipam_backend        = module.ipam.pools_level_2["ireland/backend"].id
    private_hosted_zone = aws_route53_zone.private_hosted_zone.id
    #service_network     = module.vpclattice_service_network.service_network.arn
  }
}

# Retrieving
module "retrieve_parameters" {
  source = "../modules/retrieve_parameters"

  parameters = {
    frontend_vpc             = var.frontend_account
    frontend_ava_domain_name = var.frontend_account
    frontent_alb_domain_name = var.frontend_account

    backend_vpcs         = var.backend_account
    service1_domain_name = var.backend_account
    service2_domain_name = var.backend_account
  }
}
