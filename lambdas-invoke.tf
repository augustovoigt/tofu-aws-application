locals {
  lambda_invocations = {
    rds_oracle_execute_sql_statements = {
      function_name = var.lambda_rds_oracle_execute_sql_statements
      input_parameters = {
        db_instance_identifier_destination = module.rds.db_instance_identifier
        master_secret_name                 = module.secrets["rds_app_user_master"].secret_name
        db_instance_sql_updates_statements = <<EOF
BEGIN
  -- Example: update application configuration in the database after provisioning
  UPDATE APP.CONFIG_SETTINGS
  SET SETTING_VALUE = '${lookup(local.s3_default_buckets, "files", { name = "" }).name}',
      UPDATED_AT = SYSDATE
  WHERE SETTING_KEY = 'STORAGE_DEFAULT_BUCKET'
    AND SETTING_VALUE != '${lookup(local.s3_default_buckets, "files", { name = "" }).name}';

  UPDATE APP.CONFIG_SETTINGS
  SET SETTING_VALUE = '${lookup(local.s3_default_buckets, "temp", { name = "" }).name}',
      UPDATED_AT = SYSDATE
  WHERE SETTING_KEY = 'STORAGE_TEMP_BUCKET'
    AND SETTING_VALUE != '${lookup(local.s3_default_buckets, "temp", { name = "" }).name}';

  COMMIT;
END;
  EOF
      }
    }

    rds_oracle_update_users_credentials = {
      function_name = var.lambda_rds_oracle_update_users_credentials
      input_parameters = {
        db_instance_identifier_destination = module.rds.db_instance_identifier
        master_secret_name                 = module.secrets["rds_app_user_master"].secret_name
        rds_users                          = keys(var.rds_users)
      }
    }
  }
}

resource "aws_lambda_invocation" "invoke_lambda" {
  for_each = local.lambda_invocations

  function_name = each.value.function_name
  input = jsonencode(
    merge(
      each.value.input_parameters,
      {
        trigger = timestamp()
      }
    )
  )

  lifecycle_scope = "CRUD" # This will invoke the function on each lifecycle event

  depends_on = [module.rds, module.secrets]
}
