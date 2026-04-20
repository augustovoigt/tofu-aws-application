locals {
  # Base naming convention: {resource_prefix}-app-{environment}
  # Change here to update all resource names across the module.
  naming_prefix = "${var.resource_prefix}-app-${var.environment}"

  # Path prefix used for Secrets Manager and SSM Parameter Store.
  path_prefix = "${var.resource_prefix}/${var.environment}"

  # CloudWatch Logs prefix for ECS services.
  ecs_log_group_prefix = "/aws/ecs/${var.resource_prefix}"
}
