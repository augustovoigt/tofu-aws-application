locals {
  start_stop_enabled               = var.environment_schedule.start_stop != null
  lambda_rds_dump_schedule_enabled = var.create_lambda_rds_dump_step_function && var.environment_schedule.rds_dump != null

  eventbridge_default_schedulesets = {
    rds_start_stop_instance = {
      create                     = local.start_stop_enabled
      create_bus                 = false
      create_log_delivery_source = false

      attach_lambda_policy = true
      role_name            = "${module.rds.db_instance_identifier}-schedule-rds-start-stop-instance"
      lambda_target_arns   = [var.lambda_rds_start_stop_instance_function_arn]

      schedules = local.start_stop_enabled ? {
        "${module.rds.db_instance_identifier}-start" = {
          description         = "Start RDS instance"
          schedule_expression = var.environment_schedule.start_stop.start.schedule_expression
          timezone            = var.environment_schedule.timezone
          arn                 = var.lambda_rds_start_stop_instance_function_arn
          input = jsonencode({
            action        = "start"
            db_identifier = module.rds.db_instance_identifier
          })
        }
        "${module.rds.db_instance_identifier}-stop" = {
          description         = "Stop RDS instance"
          schedule_expression = var.environment_schedule.start_stop.stop.schedule_expression
          timezone            = var.environment_schedule.timezone
          arn                 = var.lambda_rds_start_stop_instance_function_arn
          input = jsonencode({
            action        = "stop"
            db_identifier = module.rds.db_instance_identifier
          })
        }
      } : {}

      tags = {
        Name = "${module.rds.db_instance_identifier}-schedule-rds-start-stop-instance"
      }
    }

    rds_dump_step_function = {
      create                     = local.lambda_rds_dump_schedule_enabled
      create_bus                 = false
      create_log_delivery_source = false

      attach_lambda_policy = true
      role_name            = "${local.naming_prefix}-schedule-rds-dump"
      lambda_target_arns   = local.lambda_rds_dump_schedule_enabled ? [module.lambda_rds_dump_step_function.lambda_rds_dump_step_function.lambda_function_arn] : []

      schedules = local.lambda_rds_dump_schedule_enabled ? {
        "${local.naming_prefix}-rds-dump" = {
          description         = "Trigger RDS dump from production to ${var.environment}"
          schedule_expression = var.environment_schedule.rds_dump.schedule_expression
          timezone            = var.environment_schedule.timezone
          arn                 = module.lambda_rds_dump_step_function.lambda_rds_dump_step_function.lambda_function_arn
          input               = jsonencode({})
        }
      } : {}

      tags = {
        Name = "${local.naming_prefix}-schedule-rds-dump"
      }
    }
  }

  eventbridge_schedulesets = merge(local.eventbridge_default_schedulesets, var.eventbridge_schedulesets)
}

module "schedulesets" {
  source   = "terraform-aws-modules/eventbridge/aws"
  version  = "4.3.0"
  for_each = { for k, v in local.eventbridge_schedulesets : k => v if try(v.create, true) }

  create_bus                 = try(each.value.create_bus, false)
  create_log_delivery_source = try(each.value.create_log_delivery_source, false)
  role_name                  = try(each.value.role_name, null)
  attach_lambda_policy       = try(each.value.attach_lambda_policy, false)
  lambda_target_arns         = try(each.value.lambda_target_arns, [])
  schedules                  = each.value.schedules
  tags                       = try(each.value.tags, {})

  depends_on = [module.rds]
}
