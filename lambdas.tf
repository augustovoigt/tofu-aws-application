locals {
  lambda_rds_dump_step_function_aws_rds_database_values = {
    db_instance_auto_minor_version_upgrade   = tostring(coalesce(try(module.rds.db_instance_auto_minor_version_upgrade, null), var.db_instance[0].auto_minor_version_upgrade))
    db_instance_backup_retention_period      = tostring(coalesce(try(module.rds.db_instance_backup_retention_period, null), var.db_instance[0].backup_retention_period))
    db_instance_ca_cert_identifier           = coalesce(try(module.rds.db_instance_ca_cert_identifier, null), var.db_instance[0].ca_cert_identifier)
    db_instance_class                        = try(module.rds.db_instance_class, var.db_instance[0].instance_class)
    db_instance_copy_tags_to_snapshot        = tostring(coalesce(try(module.rds.db_instance_copy_tags_to_snapshot, null), var.db_instance[0].copy_tags_to_snapshot))
    db_instance_deletion_protection          = tostring(coalesce(try(module.rds.db_instance_deletion_protection, null), var.db_instance[0].deletion_protection))
    db_instance_monitoring_interval          = tostring(coalesce(try(module.rds.db_instance_monitoring_interval, null), var.db_instance[0].monitoring_interval))
    db_instance_monitoring_role_arn          = try(module.rds.db_instance_monitoring_role_arn, var.db_instance[0].monitoring_role_arn)
    db_instance_performance_insights_enabled = tostring(coalesce(try(module.rds.db_instance_performance_insights_enabled, null), var.db_instance[0].performance_insights_enabled))
    db_instance_multi_az                     = tostring(coalesce(try(module.rds.db_instance_multi_az, null), var.db_instance[0].multi_az))
    db_instance_name                         = coalesce(try(module.rds.db_instance_name, null), upper(var.environment))
    db_instance_option_group_name            = try(module.rds.db_instance_option_group_name, var.db_instance[0].option_group_name)
    db_instance_parameter_group_name         = try(module.rds.db_instance_parameter_group_name, var.db_instance[0].parameter_group_name)
    db_instance_publicly_accessible          = tostring(coalesce(try(module.rds.db_instance_publicly_accessible, null), var.db_instance[0].publicly_accessible))
    db_instance_vpc_security_group_ids       = try(module.rds.db_instance_vpc_security_group_ids, local.rds_security_group_ids)
    db_instance_storage_type                 = try(module.rds.db_instance_storage_type, var.db_instance[0].storage_type)
    db_instance_subnet_id                    = try(module.rds.db_instance_subnet_id, var.db_instance[0].db_subnet_group_name)
    db_instance_tags = jsonencode(
      merge(
        var.default_tags,
        {
          Name        = local.db_instance_identifier
          Environment = var.environment
        }
      )
    )
  }
}

module "lambda_rds_dump_step_function" {
  source = "./modules/lambdas/lambda-rds-dump-step-function"

  resource_prefix = var.resource_prefix
  environment     = var.environment

  create = var.create_lambda_rds_dump_step_function

  aws_rds_database_values = local.lambda_rds_dump_step_function_aws_rds_database_values

  db_instance_identifier_destination = local.db_instance_identifier
  db_instance_identifier_source      = "${var.resource_prefix}-app-prod"
  redis_base_key                     = local.naming_prefix

  rds_s3_integration_role_arn = lookup(var.db_instance[0].db_instance_role_associations, "S3_INTEGRATION", "")

  automatic_dump_rds_sql_updates            = var.lambda_rds_dump_sql_updates
  dump_rds_step_functions_state_machine_arn = var.step_functions_rds_dump_state_machine_arn
  redis_primary_endpoint_address            = var.valkey_endpoint

  rds_users = keys(var.rds_users)

  depends_on = [module.rds]
}
