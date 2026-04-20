resource "random_password" "rds_user_password" {
  for_each = toset([for user in keys(var.rds_users) : user if user != "master"])
  length   = 30
  upper    = true
  lower    = true
  numeric  = true
  special  = false
}

resource "random_password" "db_instance_master_credentials" {
  length  = 30
  upper   = true
  lower   = true
  numeric = true
  special = false
}

locals {
  oracle_rotation_enabled = trimspace(var.oracle_rotation_lambda_arn) != ""

  rds_user_secrets = {
    for user, user_cfg in var.rds_users :
    "rds_app_user_${user}" => {
      name                    = "${local.path_prefix}/rds/app/user/${user}"
      description             = "RDS credentials for ${user}"
      ignore_secret_changes   = true
      recovery_window_in_days = 0
      secret_string = jsonencode(
        user == "master" ? {
          username             = module.rds.db_instance_username
          password             = random_password.db_instance_master_credentials.result
          engine               = startswith(module.rds.db_instance_engine, "oracle") ? "oracle" : module.rds.db_instance_engine
          host                 = split(":", module.rds.db_instance_endpoint)[0]
          port                 = module.rds.db_instance_port
          dbname               = module.rds.db_instance_name
          dbInstanceIdentifier = module.rds.db_instance_identifier
          DB_URL               = "jdbc:oracle:thin:@${module.rds.db_instance_endpoint}:${module.rds.db_instance_name}"
          } : {
          username             = user
          password             = random_password.rds_user_password[user].result
          engine               = startswith(module.rds.db_instance_engine, "oracle") ? "oracle" : module.rds.db_instance_engine
          host                 = split(":", module.rds.db_instance_endpoint)[0]
          port                 = module.rds.db_instance_port
          dbname               = module.rds.db_instance_name
          dbInstanceIdentifier = module.rds.db_instance_identifier
          DB_URL               = "jdbc:oracle:thin:@${module.rds.db_instance_endpoint}:${module.rds.db_instance_name}"
        }
      )

      rotation = {
        enabled             = try(user_cfg.rotation_enabled, true) && local.oracle_rotation_enabled
        lambda_arn          = local.oracle_rotation_enabled ? var.oracle_rotation_lambda_arn : null
        schedule_expression = var.environment == "prod" ? user_cfg.rotation_schedule_expression_prod : user_cfg.rotation_schedule_expression_nonprod
        duration            = "1h"
        rotate_immediately  = false
      }
    }
  }

  secrets_manager_secrets = merge(local.rds_user_secrets, var.secrets_manager_secrets)
}

module "secrets" {
  source   = "terraform-aws-modules/secrets-manager/aws"
  version  = "2.1.0"
  for_each = local.secrets_manager_secrets

  name                    = each.value.name
  description             = try(each.value.description, null)
  secret_string           = each.value.secret_string
  recovery_window_in_days = try(each.value.recovery_window_in_days, 0)
  ignore_secret_changes   = try(each.value.ignore_secret_changes, true)
  kms_key_id              = try(each.value.kms_key_id, null)
  tags                    = try(each.value.tags, {})

  depends_on = [module.rds]
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = { for k, v in local.secrets_manager_secrets : k => v if try(v.rotation.enabled, false) && try(trimspace(v.rotation.lambda_arn), "") != "" }

  secret_id           = module.secrets[each.key].secret_id
  rotation_lambda_arn = each.value.rotation.lambda_arn
  rotate_immediately  = try(each.value.rotation.rotate_immediately, false)

  rotation_rules {
    schedule_expression = each.value.rotation.schedule_expression
    duration            = try(each.value.rotation.duration, "1h")
  }

  depends_on = [module.secrets]
}
