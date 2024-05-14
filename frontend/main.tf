# ---------- frontend/main.tf ----------

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
    workload = "10.0.0.0/8"
  }

  subnets = {
    public = {
      netmask                   = 24
      nat_gateway_configuration = "all_azs"
    }
    private = { netmask = 24 }
    workload = {
      netmask                 = 24
      connect_to_public_natgw = true
    }
    endpoints = { netmask = 28
    }
    transit_gateway = { netmask = 28 }
  }
}

# Associating central Private HZ (from Networking Account)
resource "aws_route53_zone_association" "frontend_vpc_association" {
  zone_id = module.retrieve_parameters.parameter.private_hosted_zone
  vpc_id  = module.frontend_vpc.vpc_attributes.id
}

# Getting CIDR block allocated to the VPC (to provide DNS server to the Client VPN endpoint)
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
    context.frontenduser.groups has "22858464-f051-706d-5718-9115ccd25a1e"
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

  application_domain     = "app.frontend.pablosc.people.aws.dev"
  domain_certificate_arn = var.certificate_arn
  endpoint_domain_prefix = ""

  attachment_type    = "vpc"
  endpoint_type      = "load-balancer"
  security_group_ids = [aws_security_group.ava_sg.id]

  load_balancer_options {
    load_balancer_arn = aws_lb.lb.arn
    port              = 443
    protocol          = "https"
    subnet_ids        = values({ for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
  }

  tags = {
    Name = "app.frontend.pablosc.people.aws.dev"
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
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "allowing_ava_egress" {
  security_group_id = aws_security_group.ava_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- VPC LATTICE VPC ASSOCIATION ---------
module "vpclattice_frontendvpc_sn_assoc" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "0.0.3"

  service_network = { identifier = module.retrieve_parameters.parameter.service_network }

  vpc_associations = {
    frontend_vpc = { vpc_id = module.frontend_vpc.vpc_attributes.id }
  }
}

# ---------- FRONTEND APPLICATION ----------
# Application Load Balancer
resource "aws_lb" "lb" {
  name               = "frontend"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = values({ for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
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
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "allowing_alb_health_check" {
  security_group_id = aws_security_group.alb_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
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

  service_connect_defaults {
    namespace = "arn:aws:servicediscovery:eu-west-1:471112834120:namespace/ns-ovswnkdt64vmtffa"
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
  task_definition     = "frontend:2"
  scheduling_strategy = "REPLICA"
  propagate_tags      = "NONE"
  iam_role            = "/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"

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
    subnets          = values({ for k, v in module.frontend_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "frontend_task_definition" {
  container_definitions = jsonencode([{
    cpu              = 0
    environment      = []
    environmentFiles = []
    essential        = true
    image            = "${aws_ecr_repository.repository.repository_url}:latest"
    logConfiguration = {
      logDriver     = "awslogs"
      secretOptions = []
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/ecs/frontend"
        awslogs-region        = "eu-west-1"
        awslogs-stream-prefix = "ecs"
      }
    }
    mountPoints = []
    name        = "frontend"
    portMappings = [{
      appProtocol   = "http"
      containerPort = 8080
      hostPort      = 8080
      name          = "frontend-8080-tcp"
      protocol      = "tcp"
    }]
    systemControls = []
    ulimits        = []
    volumesFrom    = []
  }])
  cpu                      = 1024
  execution_role_arn       = "arn:aws:iam::471112834120:role/ecsTaskExecutionRole"
  family                   = "frontend"
  memory                   = 3072
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = "arn:aws:iam::471112834120:role/frontend"
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
}

# Security Group (ECS Service)
resource "aws_security_group" "ecs_service_sg" {
  name        = "frontend-task"
  description = "Created in ECS Console"
  vpc_id      = module.frontend_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "ingress_ipv4" {
  security_group_id = aws_security_group.ecs_service_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_ipv6" {
  security_group_id = aws_security_group.ecs_service_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
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
  }
}

# Retrieving
module "retrieve_parameters" {
  source = "../modules/retrieve_parameters"

  parameters = {
    transit_gateway     = var.networking_account
    ipam_frontend       = var.networking_account
    private_hosted_zone = var.networking_account
    service_network     = var.networking_account
  }
}