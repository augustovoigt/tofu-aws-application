############################################################
# Lambda RDS Dump Step Function                           🇧🇷
############################################################

data "archive_file" "lambda_rds_dump_step_function" {
  type        = "zip"
  source_file = "${path.module}/files/lambda_function.py"
  output_path = "${path.module}/files/lambda_function.zip"
}

locals {
  lambda_function_name                      = "${var.resource_prefix}-app-${var.environment}-rds-dump-step-function"
  lambda_function_iam_role_name             = "lambda-${local.lambda_function_name}"
  create_lambda_function_effective          = var.create == null ? var.create_lambda_function : var.create
  create_lambda_function_iam_role_effective = var.create == null ? var.create_lambda_function_iam_role : var.create
}

module "lambda_rds_dump_step_function" {
  source                 = "terraform-aws-modules/lambda/aws"
  version                = "~> 8.0"
  function_name          = local.lambda_function_name
  description            = "Triggers the DUMP RDS process through the Step Functions service"
  handler                = "lambda_function.lambda_handler"
  runtime                = "python3.13"
  timeout                = 30
  create_function        = local.create_lambda_function_effective
  create_role            = false
  lambda_role            = module.iam_role_lambda_rds_dump_step_function.arn
  create_package         = false
  local_existing_package = data.archive_file.lambda_rds_dump_step_function.output_path
  environment_variables = {
    DB_INSTANCE_AUTO_MINOR_VERSION_UPGRADE   = var.aws_rds_database_values.db_instance_auto_minor_version_upgrade
    DB_INSTANCE_BACKUP_RETENTION_PERIOD      = var.aws_rds_database_values.db_instance_backup_retention_period
    DB_INSTANCE_CA_CERT_IDENTIFIER           = var.aws_rds_database_values.db_instance_ca_cert_identifier
    DB_INSTANCE_CLASS                        = var.aws_rds_database_values.db_instance_class
    DB_INSTANCE_COPY_TAGS_TO_SNAPSHOT        = var.aws_rds_database_values.db_instance_copy_tags_to_snapshot
    DB_INSTANCE_DELETE_PROTECTION            = var.aws_rds_database_values.db_instance_deletion_protection
    DB_INSTANCE_IDENTIFIER_DESTINATION       = var.db_instance_identifier_destination
    DB_INSTANCE_IDENTIFIER_SOURCE            = var.db_instance_identifier_source
    DB_INSTANCE_MONITORING_INTERVAL          = var.aws_rds_database_values.db_instance_monitoring_interval
    DB_INSTANCE_MONITORING_ROLE_ARN          = var.aws_rds_database_values.db_instance_monitoring_role_arn
    DB_INSTANCE_PERFORMANCE_INSIGHTS_ENABLED = var.aws_rds_database_values.db_instance_performance_insights_enabled
    DB_INSTANCE_MULTIAZ                      = var.aws_rds_database_values.db_instance_multi_az
    DB_INSTANCE_NAME                         = var.aws_rds_database_values.db_instance_name
    DB_INSTANCE_OG                           = var.aws_rds_database_values.db_instance_option_group_name
    DB_INSTANCE_PG                           = var.aws_rds_database_values.db_instance_parameter_group_name
    DB_INSTANCE_PUBLICLY_ACCESSIBLE          = var.aws_rds_database_values.db_instance_publicly_accessible
    DB_INSTANCE_S3_INTEGRATION_ROLE_ARN      = var.rds_s3_integration_role_arn
    DB_INSTANCE_SG                           = jsonencode(var.aws_rds_database_values.db_instance_vpc_security_group_ids)
    DB_INSTANCE_SQL_UPDATES_STATEMENTS       = var.automatic_dump_rds_sql_updates
    DB_INSTANCE_STORAGE_TYPE                 = var.aws_rds_database_values.db_instance_storage_type
    DB_INSTANCE_SUBNET_ID                    = var.aws_rds_database_values.db_instance_subnet_id
    DB_INSTANCE_TAGS                         = var.aws_rds_database_values.db_instance_tags
    DUMP_RDS_STEP_FUNCTIONS_ARN              = var.dump_rds_step_functions_state_machine_arn
    REDIS_BASE_KEY                           = var.redis_base_key
    REDIS_PRIMARY_ENDPOINT_ADDRESS           = var.redis_primary_endpoint_address
    RDS_USERS                                = jsonencode(var.rds_users)
  }

  tags = {
    Name = local.lambda_function_name
  }
}