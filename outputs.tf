# RDS

output "rds" {
  description = "Outputs from the RDS module (null when create_rds=false)"
  value       = module.rds
}

# IAM

output "iam_roles" {
  description = "Map of IAM role key -> IAM role info (includes default and additional roles)."
  value       = module.iam_roles
}

# Security Groups

output "sg_rds_primary_id" {
  description = "ID of the primary RDS security group."
  value       = try(module.security_groups["rds_primary"].security_group_id, null)
}

output "security_group_ids" {
  description = "Map of security group key -> security group ID."
  value = {
    for k, m in module.security_groups :
    k => m.security_group_id
  }
}

# Secrets Manager

output "secrets_manager_db_instance_user_credentials_arns" {
  description = "ARNs of the secrets created for RDS users."
  value = {
    for user in keys(var.rds_users) :
    user => module.secrets["rds_app_user_${user}"].secret_arn
  }
}

output "secrets_manager_secret_arns" {
  description = "Map of secret key -> secret ARN (includes default and additional secrets)."
  value = {
    for k, m in module.secrets :
    k => m.secret_arn
  }
}

# Eventbridge

output "eventbridge_lambda_rds_start_stop_instance_schedule_ids" {
  description = "IDs of the EventBridge schedules created."
  value       = try(module.schedulesets["rds_start_stop_instance"].eventbridge_rule_ids, {})
}

output "eventbridge_rule_ids" {
  description = "Map of scheduleset key -> EventBridge rule IDs map."
  value       = { for k, m in module.schedulesets : k => m.eventbridge_rule_ids }
}

# ECS

output "ecs_services" {
  description = "Map of ECS service key -> ECS service module outputs."
  value       = module.ecs_service
}

output "ecs_service_target_group_arns" {
  description = "Map of ECS logical service name -> target group ARNs (internal and public)."
  value = {
    app_backend = {
      internal = try(aws_lb_target_group.app_backend_internal[0].arn, null)
      public   = try(aws_lb_target_group.app_backend_public[0].arn, null)
    }
    app_frontend = {
      internal = try(aws_lb_target_group.app_frontend_internal[0].arn, null)
      public   = try(aws_lb_target_group.app_frontend_public[0].arn, null)
    }
  }
}

# SSM Parameter Store

output "ssm_parameter_arns" {
  description = "Map of SSM parameter key -> parameter ARN (includes default and additional parameters)."
  value = {
    for k, m in module.ssm_parameters :
    k => m.ssm_parameter_arn
  }
}

output "ssm_parameter_names" {
  description = "Map of SSM parameter key -> parameter name (includes default and additional parameters)."
  value = {
    for k, m in module.ssm_parameters :
    k => m.ssm_parameter_name
  }
}
