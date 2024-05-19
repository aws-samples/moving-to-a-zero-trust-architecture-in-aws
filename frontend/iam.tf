# ---------- frontend/iam.tf ----------

# ECS Execution Task Role
resource "aws_iam_role" "ecs_task_execution_role" {
  name        = "ecsTaskExecutionRole"
  path        = "/"
  description = "ECS Execution Role."

  managed_policy_arns = ["arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  assume_role_policy  = data.aws_iam_policy_document.ecs_task_role_assume.json
}

# ECS Execution Task Role
resource "aws_iam_role" "ecs_task_role" {
  name        = "frontend"
  path        = "/"
  description = "Allows ECS tasks to call AWS services on your behalf."

  managed_policy_arns = ["arn:aws:iam::aws:policy/VPCLatticeServicesInvokeAccess"]
  assume_role_policy  = data.aws_iam_policy_document.ecs_task_role_assume.json

  inline_policy {
    name   = "EcsExecPerms"
    policy = data.aws_iam_policy_document.ecs_task_role_inline.json
  }
}

# IAM Policies
data "aws_iam_policy_document" "ecs_task_role_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "ecs_task_role_inline" {
  statement {
    sid    = "EcsExecPerms"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel"
    ]
    resources = ["*"]
  }
}