############################################################
# Lambda RDS Dump Step Function - Outputs                 🇧🇷
############################################################

output "lambda_rds_dump_step_function" {
  value = module.lambda_rds_dump_step_function
}

output "name" {
  value = module.iam_role_lambda_rds_dump_step_function
}