<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_iam_role_lambda_rds_dump_step_function"></a> [iam\_role\_lambda\_rds\_dump\_step\_function](#module\_iam\_role\_lambda\_rds\_dump\_step\_function) | terraform-aws-modules/iam/aws//modules/iam-role | 6.4.0 |
| <a name="module_lambda_rds_dump_step_function"></a> [lambda\_rds\_dump\_step\_function](#module\_lambda\_rds\_dump\_step\_function) | terraform-aws-modules/lambda/aws | ~> 8.0 |

## Resources

| Name | Type |
|------|------|
| [archive_file.lambda_rds_dump_step_function](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_automatic_dump_rds_sql_updates"></a> [automatic\_dump\_rds\_sql\_updates](#input\_automatic\_dump\_rds\_sql\_updates) | RDS instance sql updates statements | `string` | n/a | yes |
| <a name="input_aws_rds_database_values"></a> [aws\_rds\_database\_values](#input\_aws\_rds\_database\_values) | Set of outputs from the customer RDS instance | `any` | n/a | yes |
| <a name="input_create_lambda_function"></a> [create\_lambda\_function](#input\_create\_lambda\_function) | Enable or disable the creation of the Lambda function | `bool` | `false` | no |
| <a name="input_create_lambda_function_iam_role"></a> [create\_lambda\_function\_iam\_role](#input\_create\_lambda\_function\_iam\_role) | Enable or disable the creation of the IAM role for the Lambda function | `bool` | `false` | no |
| <a name="input_customer_environment"></a> [customer\_environment](#input\_customer\_environment) | The customer environment (prod/test/homol) | `string` | n/a | yes |
| <a name="input_customer_name"></a> [customer\_name](#input\_customer\_name) | The customer name | `string` | n/a | yes |
| <a name="input_dump_rds_step_functions_state_machine_arn"></a> [dump\_rds\_step\_functions\_state\_machine\_arn](#input\_dump\_rds\_step\_functions\_state\_machine\_arn) | Step Functions state machine ARN for the Dump RDS workflow | `string` | `""` | no |
| <a name="input_dump_rds_step_functions_arn"></a> [dump\_rds\_step\_functions\_arn](#input\_dump\_rds\_step\_functions\_arn) | (Deprecated) Step Functions state machine ARN for the Dump RDS workflow. Use dump_rds_step_functions_state_machine_arn. | `string` | `""` | no |
| <a name="input_rds_s3_integration_role_arn"></a> [rds\_s3\_integration\_role\_arn](#input\_rds\_s3\_integration\_role\_arn) | IAM role ARN for rds S3 integration | `string` | n/a | yes |
| <a name="input_redis_primary_endpoint_address"></a> [redis\_primary\_endpoint\_address](#input\_redis\_primary\_endpoint\_address) | Elasticache master DNS endpoint | `string` | n/a | yes |
| <a name="input_rds_users"></a> [rds\_users](#input\_rds\_users) | List of RDS users for the oracle update users credentials lambda function. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_lambda_rds_dump_step_function"></a> [lambda\_rds\_dump\_step\_function](#output\_lambda\_rds\_dump\_step\_function) | n/a |
| <a name="output_name"></a> [name](#output\_name) | n/a |
<!-- END_TF_DOCS -->