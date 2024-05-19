# ---------- frontend/outputs.tf ----------

output "frontend_task_role" {
  description = "Frontend Task - IAM Role."
  value       = aws_iam_role.ecs_task_role.arn
}