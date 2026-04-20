locals {
  ssm_default_parameters = {
    app_rds_config = {
      create      = length(var.db_instance) > 0
      name        = "/${local.path_prefix}/rds/app/config"
      description = "Configuration parameters for the RDS app database instance. Used by version-update automation to roll back RDS changes."
      type        = "String"
      value = jsonencode({
        db_instance_class           = var.db_instance[0].instance_class
        db_instance_parameter_group = var.db_instance[0].parameter_group_name
      })
      overwrite = true
      tags      = {}
    }
  }

  ssm_parameters = merge(local.ssm_default_parameters, var.ssm_parameters)
}

module "ssm_parameters" {
  source   = "terraform-aws-modules/ssm-parameter/aws"
  version  = "2.1.0"
  for_each = { for k, v in local.ssm_parameters : k => v if try(v.create, true) }

  create          = each.value.create
  name            = each.value.name
  description     = try(each.value.description, null)
  type            = try(each.value.type, "String")
  value           = each.value.value
  overwrite       = try(each.value.overwrite, true)
  tier            = try(each.value.tier, null)
  key_id          = try(each.value.key_id, null)
  allowed_pattern = try(each.value.allowed_pattern, null)
  data_type       = try(each.value.data_type, null)
  tags            = try(each.value.tags, {})

  depends_on = [module.rds]
}