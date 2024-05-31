# ---------- frontend/main.tf ----------

data "aws_region" "current" {}

# ---------- VPC LATTICE CONFIGURATION ---------
# # Service 1
# module "vpclattice_service1" {
#   source  = "aws-ia/amazon-vpc-lattice-module/aws"
#   version = "0.1.0"

#   service_network = { identifier = module.retrieve_parameters.parameter.service_network }

#   vpc_associations = {
#     backend1_vpc = { vpc_id = module.backend1_vpc.vpc_attributes.id }
#   }

#   services = {
#     mservice1 = {
#       name               = "mservice1"
#       auth_type          = "NONE" #"AWS_IAM"
#       certificate_arn    = var.certificate_arn
#       custom_domain_name = var.backend_service1_domain_name

#       listeners = {
#         https_listener = {
#           name     = "https-443"
#           port     = 443
#           protocol = "HTTPS"
#           default_action_forward = {
#             target_groups = {
#               albtarget = { weight = 1 }
#             }
#           }
#         }
#       }
#     }
#   }

#   target_groups = {
#     albtarget = {
#       name = "mservice1"
#       type = "ALB"

#       config = {
#         port           = 443
#         protocol       = "HTTPS"
#         vpc_identifier = module.backend1_vpc.vpc_attributes.id
#       }

#       targets = {
#         albtarget = {
#           id   = aws_lb.backend1_lb.arn
#           port = 443
#         }
#       }
#     }
#   }
# }

# resource "aws_vpclattice_auth_policy" "service1_auth_policy" {
#   resource_identifier = module.vpclattice_service1.services.mservice1.attributes.arn
#   policy              = local.service1_policy
# }

# # Service 2
# module "vpclattice_service2" {
#   source  = "aws-ia/amazon-vpc-lattice-module/aws"
#   version = "0.1.0"

#   service_network = { identifier = module.retrieve_parameters.parameter.service_network }

#   services = {
#     mservice2 = {
#       name               = "mservice2"
#       auth_type          = "NONE" #"AWS_IAM"
#       certificate_arn    = var.certificate_arn
#       custom_domain_name = var.backend_service2_domain_name

#       listeners = {
#         https_listener = {
#           name     = "https-443"
#           port     = 443
#           protocol = "HTTPS"
#           default_action_forward = {
#             target_groups = {
#               lambdatarget = { weight = 1 }
#             }
#           }
#         }
#       }
#     }
#   }

#   target_groups = {
#     lambdatarget = {
#       name = "mservice2"
#       type = "LAMBDA"

#       targets = { lamdba = { id = aws_lambda_function.backend2_function.arn } }
#     }
#   }
# }

# resource "aws_vpclattice_auth_policy" "service2_auth_policy" {
#   resource_identifier = module.vpclattice_service2.services.mservice2.attributes.arn
#   policy              = local.service2_policy
# }

# ---------- BACKEND VPC (1) ----------
module "backend1_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "4.4.2"

  name     = "backend1-vpc"
  az_count = 2

  vpc_ipv4_ipam_pool_id   = module.retrieve_parameters.parameter.ipam_backend
  vpc_ipv4_netmask_length = 16

  transit_gateway_id = module.retrieve_parameters.parameter.transit_gateway
  transit_gateway_routes = {
    private     = "10.0.0.0/8"
    application = "10.0.0.0/8"
  }

  subnets = {
    public = {
      netmask                   = 28
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
resource "awscc_route53profiles_profile_association" "backend1_r53_profile_association" {
  name        = "r53_profile_backend1_association"
  profile_id  = module.retrieve_parameters.parameter.r53_profile
  resource_id = module.backend1_vpc.vpc_attributes.id
}

# Getting CIDR block allocated to the VPC
data "aws_vpc" "backend1_vpc" {
  id = module.backend1_vpc.vpc_attributes.id
}

# ---------- BACKEND APPLICATION 1 ----------
# Application Load Balancer
resource "aws_lb" "backend1_lb" {
  name               = "mservice1"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend1_alb_sg.id]
  subnets            = values({ for k, v in module.backend1_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "private" })
  ip_address_type    = "ipv4"
}

# Target Group
resource "aws_lb_target_group" "backend1_target_group" {
  name        = "mservice1"
  port        = 8081
  protocol    = "HTTP"
  vpc_id      = module.backend1_vpc.vpc_attributes.id
  target_type = "ip"
}

# Listener
resource "aws_lb_listener" "backend1_listener" {
  load_balancer_arn = aws_lb.backend1_lb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend1_target_group.arn
  }
}

# Security Group
resource "aws_security_group" "backend1_alb_sg" {
  name        = "mservice1-alb"
  description = "allows access to the load balancer"
  vpc_id      = module.backend1_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "backend1_allowing_ingress_alb_https" {
  security_group_id = aws_security_group.backend1_alb_sg.id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "backend1_allowing_alb_health_check" {
  security_group_id = aws_security_group.backend1_alb_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = data.aws_vpc.backend1_vpc.cidr_block
}

# ECR respository
resource "aws_ecr_repository" "repository" {
  name = "mservice1"
}

# ECS Cluster
resource "aws_ecs_cluster" "backend1_cluster" {
  name = "mservice1"

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }
}

resource "aws_ecs_cluster_capacity_providers" "cluster_capacity_provider" {
  cluster_name       = aws_ecs_cluster.backend1_cluster.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# ECS Service
resource "aws_ecs_service" "backend1_service" {
  cluster             = aws_ecs_cluster.backend1_cluster.arn
  name                = "mservice1"
  platform_version    = "LATEST"
  task_definition     = split("/", aws_ecs_task_definition.backend1_task_definition.arn)[1]
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
    container_name   = "mservice1"
    container_port   = 8081
    target_group_arn = aws_lb_target_group.backend1_target_group.arn
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.backend1_ecs_service_sg.id]
    subnets          = values({ for k, v in module.backend1_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "application" })
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "backend1_task_definition" {
  family                   = "mservice1"
  cpu                      = 1024
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  memory                   = 3072
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name      = "mservice1"
    image     = "${aws_ecr_repository.repository.repository_url}:latest"
    essential = true

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-create-group  = "true"
        awslogs-group         = "/ecs/mservice1"
        awslogs-region        = data.aws_region.current.name
        awslogs-stream-prefix = "ecs"
      }
    }

    portMappings = [{
      appProtocol   = "http"
      containerPort = 8081
      hostPort      = 8081
      name          = "mservice1-8081-tcp"
      protocol      = "tcp"
    }]
  }])

  runtime_platform {
    cpu_architecture        = "X86_64"
    operating_system_family = "LINUX"
  }
}

# Security Group (ECS Service)
resource "aws_security_group" "backend1_ecs_service_sg" {
  name        = "mservice1"
  description = "Created in ECS Console"
  vpc_id      = module.backend1_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "ingress_ipv4" {
  security_group_id = aws_security_group.backend1_ecs_service_sg.id

  ip_protocol = "tcp"
  from_port   = 8081
  to_port     = 8081
  cidr_ipv4   = data.aws_vpc.backend1_vpc.cidr_block
}

resource "aws_vpc_security_group_egress_rule" "egress_ipv4" {
  security_group_id = aws_security_group.backend1_ecs_service_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

# ---------- BACKEND VPC (2) ----------
module "backend2_vpc" {
  source  = "aws-ia/vpc/aws"
  version = "4.4.2"

  name     = "backend2-vpc"
  az_count = 2

  vpc_ipv4_ipam_pool_id   = module.retrieve_parameters.parameter.ipam_backend
  vpc_ipv4_netmask_length = 16

  transit_gateway_id = module.retrieve_parameters.parameter.transit_gateway
  transit_gateway_routes = {
    private = "0.0.0.0/0"
  }

  subnets = {
    private         = { netmask = 24 }
    endpoints       = { netmask = 28 }
    transit_gateway = { netmask = 28 }
  }
}

# Associating central Route53 Profile (from Networking Account)
resource "awscc_route53profiles_profile_association" "backend2_r53_profile_association" {
  name        = "r53_profile_backend2_association"
  profile_id  = module.retrieve_parameters.parameter.r53_profile
  resource_id = module.backend2_vpc.vpc_attributes.id
}

# Getting CIDR block allocated to the VPC
data "aws_vpc" "backend2_vpc" {
  id = module.backend2_vpc.vpc_attributes.id
}

# ---------- BACKEND APPLICATION 2 ----------
# Application Load Balancer
resource "aws_lb" "backend2_lb" {
  name               = "mservice2"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend2_alb_sg.id]
  subnets            = values({ for k, v in module.backend2_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "private" })
  ip_address_type    = "ipv4"
}

# Target Group
resource "aws_lb_target_group" "backend2_target_group" {
  name        = "mservice2"
  target_type = "lambda"
}

# Listener
resource "aws_lb_listener" "backend2_listener" {
  load_balancer_arn = aws_lb.backend2_lb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend2_target_group.arn
  }
}

# Security Group (Application Load Balancer)
resource "aws_security_group" "backend2_alb_sg" {
  name        = "mservice2-alb"
  description = "allows access to the mservice2 elb"
  vpc_id      = module.backend2_vpc.vpc_attributes.id
}

resource "aws_vpc_security_group_ingress_rule" "backend2_ingress" {
  security_group_id = aws_security_group.backend2_alb_sg.id

  from_port   = 443
  to_port     = 443
  ip_protocol = "tcp"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "backend2_egress" {
  security_group_id = aws_security_group.backend2_alb_sg.id

  ip_protocol = "-1"
  cidr_ipv4   = data.aws_vpc.backend2_vpc.cidr_block
}

# ALB target attachment (Lambda function)
resource "aws_lb_target_group_attachment" "backend2_tg_attachment" {
  target_group_arn = aws_lb_target_group.backend2_target_group.arn
  target_id        = aws_lambda_function.backend2_function.arn

  depends_on = [aws_lambda_permission.lambda_target_alb]
}

resource "aws_lambda_permission" "lambda_target_alb" {
  statement_id  = "AllowExecutionFromlb"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend2_function.function_name
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.backend2_target_group.arn
}

# Lambda function
resource "aws_lambda_function" "backend2_function" {
  function_name = "mservice2"
  handler       = "app2lambda.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 128
  timeout       = 10

  role             = aws_iam_role.lambda_role.arn
  filename         = "lambda_function.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "../applications/mservice2/app2lambda.py"
  output_path = "lambda_function.zip"
}

# ---------- PARAMETERS ----------
# Sharing
module "share_parameters" {
  source = "../modules/share_parameter"

  parameters = {
    backend_vpcs = jsonencode({
      backend1_vpc = {
        vpc_id                        = module.backend1_vpc.vpc_attributes.id
        transit_gateway_attachment_id = module.backend1_vpc.transit_gateway_attachment_id
      }
      backend2_vpc = {
        vpc_id                        = module.backend2_vpc.vpc_attributes.id
        transit_gateway_attachment_id = module.backend2_vpc.transit_gateway_attachment_id
      }
    })
    #service1_domain_name = module.vpclattice_service1.services.mservice1.attributes.dns_entry[0].domain_name
    #service2_domain_name = module.vpclattice_service2.services.mservice2.attributes.dns_entry[0].domain_name
    service1_domain_name = aws_lb.backend1_lb.dns_name
    service2_domain_name = aws_lb.backend2_lb.dns_name
  }
}

# Retrieving
module "retrieve_parameters" {
  source = "../modules/retrieve_parameters"

  parameters = {
    transit_gateway     = var.networking_account
    ipam_backend        = var.networking_account
    private_hosted_zone = var.networking_account
    r53_profile         = var.networking_account
    #service_network    = var.networking_account
  }
}

