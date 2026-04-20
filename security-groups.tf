locals {
  security_groups_default = {
    rds_primary = {
      create                   = var.create_sg_rds_primary
      name                     = "${var.resource_prefix}-${var.environment}-rds-primary"
      description              = "Primary security group for the ${var.environment} RDS database for customer ${var.resource_prefix}."
      vpc_id                   = var.vpc_id
      use_name_prefix          = false
      ingress_with_cidr_blocks = []
      egress_with_cidr_blocks = [
        {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          description = "Allow all outbound traffic"
          cidr_blocks = "0.0.0.0/0"
        }
      ]
      tags = {
        Name = "${var.resource_prefix}-${var.environment}-rds-primary"
      }
    }
    ecs_services = {
      create          = var.create_ecs_services
      name            = "${var.resource_prefix}-${var.environment}-ecs-services"
      description     = "Security group attached to ECS services for ${var.resource_prefix} in ${var.environment}."
      vpc_id          = var.vpc_id
      use_name_prefix = false
      egress_with_cidr_blocks = [
        {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          description = "Allow all outbound traffic"
          cidr_blocks = "0.0.0.0/0"
        }
      ]
      tags = {
        Name = "${var.resource_prefix}-${var.environment}-ecs-services"
      }
    }
    rds_external_access = {
      create          = var.create_sg_rds_external_access
      name            = "${var.resource_prefix}-${var.environment}-rds-external-access"
      description     = "Allow external IP access to the RDS database on port 1521 for ${var.resource_prefix} in ${var.environment}."
      vpc_id          = var.vpc_id
      use_name_prefix = false
      ingress_with_cidr_blocks = [for cidr in var.rds_external_access_cidrs : {
        from_port   = 1521
        to_port     = 1521
        protocol    = "tcp"
        description = "Allow Oracle connections from ${cidr}"
        cidr_blocks = cidr
      }]
      egress_with_cidr_blocks = [
        {
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          description = "Allow all outbound traffic"
          cidr_blocks = "0.0.0.0/0"
        }
      ]
      tags = {
        Name = "${var.resource_prefix}-${var.environment}-rds-external-access"
      }
    }
  }

  security_groups = merge(local.security_groups_default, var.security_groups)
}

module "security_groups" {
  source   = "terraform-aws-modules/security-group/aws"
  version  = "5.3.1"
  for_each = { for k, v in local.security_groups : k => v if try(v.create, true) }

  name                     = each.value.name
  description              = each.value.description
  vpc_id                   = each.value.vpc_id
  use_name_prefix          = try(each.value.use_name_prefix, false)
  ingress_with_cidr_blocks = try(each.value.ingress_with_cidr_blocks, [])
  egress_with_cidr_blocks  = try(each.value.egress_with_cidr_blocks, [])
  tags                     = try(each.value.tags, {})
}

resource "aws_vpc_security_group_ingress_rule" "rds_primary_from_ecs_services" {
  count = var.create_ecs_services && var.create_sg_rds_primary ? 1 : 0

  security_group_id            = module.security_groups["rds_primary"].security_group_id
  referenced_security_group_id = module.security_groups["ecs_services"].security_group_id
  from_port                    = 1521
  to_port                      = 1521
  ip_protocol                  = "tcp"
  description                  = "Allow Oracle connections from ECS services."
}

resource "aws_vpc_security_group_ingress_rule" "valkey_from_ecs_services" {
  count = var.create_ecs_services && var.valkey_security_group_id != null ? 1 : 0

  security_group_id            = var.valkey_security_group_id
  referenced_security_group_id = module.security_groups["ecs_services"].security_group_id
  from_port                    = 6379
  to_port                      = 6379
  ip_protocol                  = "tcp"
  description                  = "Allow Valkey connections from ECS services."
}