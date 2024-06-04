# ---------- frontend/main.tf ----------

data "aws_region" "current" {}

# ---------- FRONTEND VPC ----------
module "frontend_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "4.4.2"

  name     = "frontend-vpc"
  az_count = 2

  vpc_ipv4_ipam_pool_id   = module.retrieve_parameters.parameter.ipam_frontend
  vpc_ipv4_netmask_length = 16

  transit_gateway_id = module.retrieve_parameters.parameter.transit_gateway
  transit_gateway_routes = {
    application = "10.0.0.0/8"
  }

  # vpc_lattice = {
  #   service_network_identifier = module.retrieve_parameters.parameter.service_network
  # }

  subnets = {
    public = {
      netmask                   = 24
      nat_gateway_configuration = "all_azs"
    }
    private = { netmask = 24 }
    application = {
      netmask                 = 24
      connect_to_public_natgw = true
    }
    endpoints       = { netmask = 28 }
    transit_gateway = { netmask = 28 }
  }
}

# Associating central Route53 Profile (from Networking Account)
resource "awscc_route53profiles_profile_association" "r53_profile_association" {
  name        = "r53_profile_frontend_association"
  profile_id  = module.retrieve_parameters.parameter.r53_profile
  resource_id = module.frontend_vpc.vpc_attributes.id
}

# Getting CIDR block allocated to the VPC
data "aws_vpc" "vpc" {
  id = module.frontend_vpc.vpc_attributes.id
}

# ---------- CLIENT VPN ----------
resource "aws_ec2_client_vpn_endpoint" "clientvpn" {
  description            = "client-vpn"
  server_certificate_arn = var.client_vpn.server_certificate_arn
  client_cidr_block      = var.client_vpn.cidr_block

  self_service_portal = "enabled"
  split_tunnel        = false

  authentication_options {
    type                           = "federated-authentication"
    saml_provider_arn              = var.client_vpn.saml_provider_arn
    self_service_saml_provider_arn = var.client_vpn.self_service_saml_provider_arn
  }

  dns_servers = [cidrhost(data.aws_vpc.vpc.cidr_block, 2)]

  connection_log_options {
    enabled = false
  }

  tags = {
    Name = "client-vpn-endpoint"
  }
}

resource "aws_ec2_client_vpn_network_association" "clientvpn_network_association" {
  for_each = { for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "private" }

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.clientvpn.id
  subnet_id              = each.value
}

resource "aws_ec2_client_vpn_authorization_rule" "clientvpn_authorization_rule" {
  description            = "Client VPN Authorization (All)"
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.clientvpn.id
  target_network_cidr    = var.client_vpn.target_network_cidr
  access_group_id        = var.client_vpn.access_group_id
}

# ---------- AWS VERIFIED ACCESS ----------
# Instance
resource "aws_verifiedaccess_instance" "ava_instance" {
  description = "AVA Instance"

  tags = {
    Name = "ava-instance"
  }
}

# Trust Provider
resource "aws_verifiedaccess_trust_provider" "trust_provider" {
  description              = "AVA Trust Provider - User (IAM Identity Center)"
  policy_reference_name    = "frontenduser"
  trust_provider_type      = "user"
  user_trust_provider_type = "iam-identity-center"

  tags = {
    Name = "ava-trust-provider"
  }
}

resource "aws_verifiedaccess_instance_trust_provider_attachment" "trust_provider_attachment" {
  verifiedaccess_instance_id       = aws_verifiedaccess_instance.ava_instance.id
  verifiedaccess_trust_provider_id = aws_verifiedaccess_trust_provider.trust_provider.id
}

# Group
resource "aws_verifiedaccess_group" "ava_group" {
  description                = "AVA Group"
  verifiedaccess_instance_id = aws_verifiedaccess_instance.ava_instance.id

  policy_document = <<EOT
permit(principal,action,resource)
when {
    context.frontenduser.groups has "${var.idc_group_id}"
};
EOT

  tags = {
    Name = "ava-group"
  }

  depends_on = [aws_verifiedaccess_instance_trust_provider_attachment.trust_provider_attachment]
}

resource "aws_verifiedaccess_endpoint" "ava_endpoint" {
  description              = "App Frontend"
  verified_access_group_id = aws_verifiedaccess_group.ava_group.id

  application_domain     = var.frontend_domain_name
  domain_certificate_arn = var.certificate_arn
  endpoint_domain_prefix = "frontend"

  attachment_type    = "vpc"
  endpoint_type      = "load-balancer"
  security_group_ids = [aws_security_group.ava_sg.id]

  load_balancer_options {
    load_balancer_arn = aws_lb.lb.arn
    port              = 443
    protocol          = "https"
    subnet_ids        = values({ for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "private" })
  }

  tags = {
    Name = "App Frontend"
  }
}

# Security Group
resource "aws_security_group" "ava_sg" {
  name        = "ava-security-group"
  description = "AWS Verified Access endpoint"
  vpc_id      = module.frontend_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_https" {
  security_group_id = aws_security_group.ava_sg.id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = data.aws_vpc.vpc.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "allowing_ava_alb_connectivity" {
  security_group_id = aws_security_group.ava_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = data.aws_vpc.vpc.cidr_block
}

# ---------- FRONTEND APPLICATION ----------
# Application Load Balancer
resource "aws_lb" "lb" {
  name               = "frontend"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = values({ for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "private" })
  ip_address_type    = "ipv4"
}

# Target Group
resource "aws_lb_target_group" "target_group" {
  name        = "frontend-targets"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.frontend_vpc.vpc_attributes.id
  target_type = "ip"
}

# Listener
resource "aws_lb_listener" "frontend_listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.target_group.arn

  }
}

# Security Group (Application Load Balancer)
resource "aws_security_group" "alb_sg" {
  name        = "frontend-elb-secgroup"
  description = "allows port 80 connectivity"
  vpc_id      = module.frontend_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "allowing_ingress_alb_https" {
  security_group_id = aws_security_group.alb_sg.id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = data.aws_vpc.vpc.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "allowing_alb_health_check" {
  security_group_id = aws_security_group.alb_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = data.aws_vpc.vpc.cidr_block
}

# ECR respository
resource "aws_ecr_repository" "repository" {
  name = "frontend"
}

# ECS Cluster
resource "aws_ecs_cluster" "frontend_cluster" {
  name = "frontend"

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_provider" {
  cluster_name       = aws_ecs_cluster.frontend_cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# ECS Service
resource "aws_ecs_service" "frontend_service" {
  cluster             = aws_ecs_cluster.frontend_cluster.arn
  name                = "frontend"
  platform_version    = "LATEST"
  task_definition     = split("/", aws_ecs_task_definition.frontend_task_definition.arn)[1]
  scheduling_strategy = "REPLICA"
  propagate_tags      = "NONE"

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  desired_count                      = 2
  enable_ecs_managed_tags            = true
  enable_execute_command             = true

  capacity_provider_strategy {
    base              = 0
    capacity_provider = "FARGATE"
    weight            = 1
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  load_balancer {
    container_name   = "frontend"
    container_port   = 8080
    target_group_arn = aws_lb_target_group.target_group.arn
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service_sg.id]
    subnets          = values({ for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "application" })
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "frontend_task_definition" {
  cpu                      = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  family                   = "frontend"
  memory                   = 3072
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${aws_ecr_repository.repository.repository_url}:latest"
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/ecs/frontend"
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "ecs"
      }
    }

    portMappings = [{
      appProtocol   = "http"
      containerPort = 8080
      hostPort      = 8080
      name          = "frontend-8080-tcp"
      protocol      = "tcp"
    }]
  }])
}

# Security Group (ECS Service)
resource "aws_security_group" "ecs_service_sg" {
  name        = "frontend-task"
  description = "Created in ECS Console"
  vpc_id      = module.frontend_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "ingress_ipv4" {
  security_group_id = aws_security_group.ecs_service_sg.id

  ip_protocol = "tcp"
  from_port   = 8080
  to_port     = 8080
  cidr_ipv4   = data.aws_vpc.vpc.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "egress_ipv4" {
  security_group_id = aws_security_group.ecs_service_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- PARAMETERS ----------
# Sharing
module "share_parameters" {
  source = "../modules/share_parameter"

  parameters = {
    frontend_vpc = jsonencode({
      vpc_id                        = module.frontend_vpc.vpc_attributes.id
      transit_gateway_attachment_id = module.frontend_vpc.transit_gateway_attachment_id
    })
    frontend_ava_domain_name = aws_verifiedaccess_endpoint.ava_endpoint.endpoint_domain
    frontent_alb_domain_name = aws_lb.lb.dns_name
  }
}

# Retrieving
module "retrieve_parameters" {
  source = "../modules/retrieve_parameters"

  parameters = {
    transit_gateway = var.networking_account
    ipam_frontend   = var.networking_account
    r53_profile     = var.networking_account
    #service_network = var.networking_account
  }
}