# ---------- frontend/main.tf ----------

# ---------- VPC LATTICE CONFIGURATION ---------
# Backend VPC 1 & Backend Service 1 association
module "vpclattice_backend1vpc" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "0.0.3"

  service_network = { identifier = module.retrieve_parameters.parameter.service_network }

  vpc_associations = {
    backend_vpc = { vpc_id = module.backend1_vpc.vpc_attributes.id }
  }

  services = {
    mservice1 = {
      name      = "mservice1"
      auth_type = "NONE"
      #auth_policy = 
      certificate_arn    = var.certificate_arn
      custom_domain_name = "mservice1.backend.pablosc.people.aws.dev"

      listeners = {
        https_listener = {
          name     = "https-443"
          port     = 443
          protocol = "HTTPS"
          default_action_forward = {
            target_groups = {
              albtarget = { weight = 1 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    albtarget = {
      name = "mservice1"
      type = "ALB"

      config = {
        port           = 443
        protocol       = "HTTPS"
        vpc_identifier = module.backend1_vpc.vpc_attributes.id
      }

      targets = {
        albtarget = {
          id   = aws_lb.backend1_lb.arn
          port = 443
        }
      }
    }
  }
}

# Backend Service 2 association
module "vpclattice_backend2" {
  source  = "aws-ia/amazon-vpc-lattice-module/aws"
  version = "0.0.3"

  service_network = { identifier = module.retrieve_parameters.parameter.service_network }

  services = {
    mservice1 = {
      name      = "mservice2"
      auth_type = "NONE"
      #auth_policy = 
      certificate_arn    = var.certificate_arn
      custom_domain_name = "mservice2.backend.pablosc.people.aws.dev"

      listeners = {
        https_listener = {
          name     = "https-443"
          port     = 443
          protocol = "HTTPS"
          default_action_forward = {
            target_groups = {
              lambdatarget = { weight = 1 }
            }
          }
        }
      }
    }
  }

  target_groups = {
    lambdatarget = {
      name = "mservice2"
      type = "LAMBDA"

      targets = { lambda = { id = aws_lambda_function.backend2_function.arn } }
    }
  }
}

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
    private  = "10.0.0.0/8"
    workload = "10.0.0.0/8"
  }

  subnets = {
    public = {
      netmask                   = 28
      nat_gateway_configuration = "all_azs"
    }
    private = { netmask = 24 }
    workload = {
      netmask                 = 24
      connect_to_public_natgw = true
    }
    endpoints       = { netmask = 28 }
    transit_gateway = { netmask = 28 }
  }
}

# Associating central Private HZ (from Networking Account)
resource "aws_route53_zone_association" "backend1_vpc_association" {
  zone_id = module.retrieve_parameters.parameter.private_hosted_zone
  vpc_id  = module.backend1_vpc.vpc_attributes.id
}

# ---------- BACKEND APPLICATION 1 ----------
# Application Load Balancer
resource "aws_lb" "backend1_lb" {
  name               = "mservice1"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.backend1_alb_sg.id]
  subnets            = values({ for k, v in module.backend1_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
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
  cidr_ipv4   = "0.0.0.0/0"
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

  service_connect_defaults {
    namespace = "arn:aws:servicediscovery:eu-west-1:992382807606:namespace/ns-am4q2r72hxxjv3jr"
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
  task_definition     = "mservice1:1"
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
    container_name   = "mservice1"
    container_port   = 8081
    target_group_arn = aws_lb_target_group.backend1_target_group.arn
  }

  network_configuration {
    assign_public_ip = false
    security_groups  = [aws_security_group.backend1_ecs_service_sg.id]
    subnets          = values({ for k, v in module.backend1_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
  }
}

# ECS Task Definition
resource "aws_ecs_task_definition" "backend1_task_definition" {
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
        awslogs-group         = "/ecs/mservice1"
        awslogs-region        = "eu-west-1"
        awslogs-stream-prefix = "ecs"
      }
    }
    mountPoints = []
    name        = "mservice1"
    portMappings = [{
      appProtocol   = "http"
      containerPort = 8081
      hostPort      = 8081
      name          = "mservice1-8081-tcp"
      protocol      = "tcp"
    }]
    systemControls = []
    ulimits        = []
    volumesFrom    = []
  }])
  cpu                      = 1024
  execution_role_arn       = "arn:aws:iam::992382807606:role/ecsTaskExecutionRole"
  family                   = "mservice1"
  memory                   = 3072
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  task_role_arn            = "arn:aws:iam::992382807606:role/mservice1"
  runtime_platform {
    cpu_architecture        = "ARM64"
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

  ip_protocol = "-1"
  cidr_ipv4   = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "ingress_ipv6" {
  security_group_id = aws_security_group.backend1_ecs_service_sg.id

  ip_protocol = "-1"
  cidr_ipv6   = "::/0"
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
    private  = "0.0.0.0/0"
    workload = "0.0.0.0/0"
  }

  subnets = {
    private         = { netmask = 24 }
    workload        = { netmask = 24 }
    endpoints       = { netmask = 28 }
    transit_gateway = { netmask = 28 }
  }
}

# Associating central Private HZ (from Networking Account)
resource "aws_route53_zone_association" "backend2_vpc_association" {
  zone_id = module.retrieve_parameters.parameter.private_hosted_zone
  vpc_id  = module.backend2_vpc.vpc_attributes.id
}

# ---------- BACKEND APPLICATION 2 ----------
# Application Load Balancer
resource "aws_lb" "backend2_lb" {
  name               = "mservice2"
  internal           = true
  load_balancer_type = "application"
  security_groups    = ["sg-0f08ab7a00e413c34"]
  subnets            = values({ for k, v in module.backend2_vpc.private_subnet_attributes_by_az : split("/", k)[1] => v.id if split("/", k)[0] == "workload" })
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
  cidr_ipv4   = "0.0.0.0/0"
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
  function_name = "arn:aws:lambda:eu-west-1:992382807606:function:mservice2"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.12"
  memory_size   = 128
  timeout       = 3

  role             = "arn:aws:iam::992382807606:role/service-role/mservice2-role-5hna1btr"
  filename         = "lambda_function.zip"
  source_code_hash = data.archive_file.lambda.output_base64sha256
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "../applications/backend2/lambda_function.py"
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
    service_network     = var.networking_account
  }
}

