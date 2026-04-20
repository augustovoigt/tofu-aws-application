############################################################
# Lambda RDS Dump Step Function - Variables               🇧🇷
############################################################

variable "resource_prefix" {
  description = "The resource prefix"
  type        = string
}

variable "environment" {
  description = "The environment (prod/test/homol)"
  type        = string
}

variable "create_lambda_function_iam_role" {
  description = "Enable or disable the creation of the IAM role for the Lambda function"
  type        = bool
  default     = false
}

variable "create_lambda_function" {
  description = "Enable or disable the creation of the Lambda function"
  type        = bool
  default     = false
}

variable "create" {
  description = "Master switch to create this lambda (function and IAM role). When set, it overrides create_lambda_function and create_lambda_function_iam_role."
  type        = bool
  default     = null
}

variable "aws_rds_database_values" {
  description = "Set of outputs from the customer RDS instance"
}

variable "db_instance_identifier_destination" {
  description = "RDS instance identifier for the destination (current environment)"
  type        = string
}

variable "db_instance_identifier_source" {
  description = "RDS instance identifier for the source (production environment)"
  type        = string
}

variable "redis_base_key" {
  description = "Base key prefix used for Redis/Valkey cache entries"
  type        = string
}

variable "rds_s3_integration_role_arn" {
  description = "IAM role ARN for rds S3 integration"
  type        = string
}

variable "automatic_dump_rds_sql_updates" {
  description = "RDS instance sql updates statements"
  type        = string
}

variable "dump_rds_step_functions_state_machine_arn" {
  description = "Step Functions state machine ARN for the Dump RDS workflow"
  type        = string
  default     = ""
}


variable "redis_primary_endpoint_address" {
  description = "Elasticache master DNS endpoint"
  type        = string
}

variable "rds_users" {
  description = "List of RDS users for the oracle update users credentials lambda function."
  type        = list(string)
  default     = []
}