locals {
  db_instance_identifier           = local.naming_prefix
  final_snapshot_identifier_prefix = "${local.naming_prefix}-final-snapshot-deleted-by-terraform"

  managed_rds_security_group_ids = compact(concat(
    var.create_sg_rds_primary ? [module.security_groups["rds_primary"].security_group_id] : [],
    var.create_sg_rds_external_access ? [module.security_groups["rds_external_access"].security_group_id] : [],
  ))

  rds_security_group_ids = distinct(concat(
    var.db_instance[0].vpc_security_group_ids,
    local.managed_rds_security_group_ids
  ))

  # Uses AWS CLI JMESPath to:
  # 1) keep only EngineVersion values containing "rur"
  # 1b) keep only versions with Status == "available"
  # 2) sort them and pick the last (most recent)
  # It returns a JSON object that matches the `external` data source contract.
  rds_engine_version_rur_query = "{engine_version: (sort_by(DBEngineVersions[?Status=='available' && contains(EngineVersion, 'rur')], &EngineVersion)[-1].EngineVersion) || 'NOT_FOUND'}"

  unsupported_perf_insights_instances = [
    "db.t3.micro", "db.t3.small",
    "db.t2.micro", "db.t2.small"
  ]
  performance_insights_supported = !contains(
    local.unsupported_perf_insights_instances,
    var.db_instance[0].instance_class
  )

  performance_insights_enabled = (
    local.performance_insights_supported && var.db_instance[0].performance_insights_enabled
  )

  computed_iops = try(var.db_instance[0].iops, null) != null ? var.db_instance[0].iops : (
    contains(["mysql", "postgres"], var.db_instance[0].engine) ? null : (
      var.db_instance[0].allocated_storage < 200 ? 3000 : 12000
    )
  )

  computed_storage_throughput = try(var.db_instance[0].storage_throughput, null) != null ? var.db_instance[0].storage_throughput : (
    contains(["mysql", "postgres"], var.db_instance[0].engine) ? null : (
      var.db_instance[0].allocated_storage < 200 ? 125 : 500
    )
  )

  rds_kms_key_id = try(trimspace(var.db_instance[0].kms_key_id), "") != "" ? var.db_instance[0].kms_key_id : null
}

data "external" "db_instance_engine_version" {
  program = [
    "aws",
    "rds",
    "describe-db-engine-versions",
    "--engine",
    var.db_instance[0].engine,
    "--engine-version",
    var.db_instance[0].engine_version,
    "--region",
    var.aws_region,
    "--query",
    local.rds_engine_version_rur_query,
    "--output",
    "json",
  ]
}

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "7.1.0"

  # Creation / identification
  create_db_instance = true
  identifier         = local.db_instance_identifier
  db_name            = upper(var.environment)

  # Engine
  engine               = var.db_instance[0].engine
  engine_version       = data.external.db_instance_engine_version.result.engine_version
  license_model        = var.db_instance[0].license_model
  major_engine_version = var.db_instance[0].engine_version

  # Parameter / option groups
  create_db_parameter_group = false
  create_db_option_group    = false
  parameter_group_name      = var.db_instance[0].parameter_group_name
  option_group_name         = var.db_instance[0].option_group_name

  # Instance sizing / storage
  instance_class     = var.db_instance[0].instance_class
  allocated_storage  = var.db_instance[0].allocated_storage
  storage_type       = var.db_instance[0].storage_type
  iops               = local.computed_iops
  storage_throughput = local.computed_storage_throughput
  multi_az           = var.db_instance[0].multi_az

  # Minor upgrades / certificates
  auto_minor_version_upgrade = var.db_instance[0].auto_minor_version_upgrade
  ca_cert_identifier         = var.db_instance[0].ca_cert_identifier

  # Encryption
  kms_key_id = local.rds_kms_key_id

  # Credentials (ignored when restoring from snapshot)
  username                    = var.db_instance[0].snapshot_identifier != "" ? null : var.db_instance[0].username
  password_wo                 = random_password.db_instance_master_credentials.result
  password_wo_version         = 1
  manage_master_user_password = false

  # Networking
  db_subnet_group_name   = var.db_instance[0].db_subnet_group_name
  publicly_accessible    = var.db_instance[0].publicly_accessible
  vpc_security_group_ids = local.rds_security_group_ids

  # Backups / snapshots
  snapshot_identifier     = var.db_instance[0].snapshot_identifier
  backup_retention_period = var.db_instance[0].backup_retention_period
  copy_tags_to_snapshot   = var.db_instance[0].copy_tags_to_snapshot

  # Lifecycle / protection
  deletion_protection              = var.db_instance[0].deletion_protection
  skip_final_snapshot              = var.db_instance[0].skip_final_snapshot
  final_snapshot_identifier_prefix = local.final_snapshot_identifier_prefix

  # Monitoring
  # create_monitoring_role           = true
  # monitoring_role_use_name_prefix  = true
  monitoring_interval = var.db_instance[0].monitoring_interval
  monitoring_role_arn = var.db_instance[0].monitoring_role_arn

  # Performance Insights
  performance_insights_enabled = var.db_instance[0].performance_insights_enabled

  # IAM associations
  db_instance_role_associations = var.db_instance[0].db_instance_role_associations

  tags = {
    Name = local.db_instance_identifier
  }

  timeouts = {
    create = "3h"
  }

  depends_on = [random_password.db_instance_master_credentials, module.security_groups]
}