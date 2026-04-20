# tofu-aws-application

OpenTofu module for provisioning the application infrastructure on AWS. Supports both EKS and ECS deployment models through feature flags.

## What this module creates

| Resource | Description | Feature flag |
|---|---|---|
| **Oracle RDS** | Single-instance Oracle database (new or restored from snapshot) | Always created |
| **Secrets Manager** | RDS user credentials with optional automatic rotation | Always created |
| **SSM Parameter Store** | RDS configuration parameters for automation | Always created |
| **Security Groups** | RDS primary, external access, and ECS services | `create_sg_rds_*`, `create_ecs_services` |
| **S3 Buckets** | `files` and `temp` buckets for application file storage | `create_bucket_files`, `create_bucket_temp` |
| **IAM Roles** | EKS service account role, custom roles | `create_iam_role_eks_service_account` |
| **Kubernetes Namespace** | Application namespace with config map | `create_kubernetes_resources` |
| **ECS Services** | Backend, frontend | `create_ecs_services` |
| **ALB Target Groups & Rules** | Internal and public ALB listener rules for ECS | `create_ecs_services` + `alb_*_https_listener_arn` |
| **Route53 Records** | DNS ALIAS records for ECS services | `internal_route53_zone`, `public_route53_zone` |
| **EventBridge Schedules** | RDS start/stop, RDS dump automation | `environment_schedule.start_stop`, `environment_schedule.rds_dump` |
| **Lambda (RDS Dump)** | Triggers production-to-replica database dump via Step Functions | `create_lambda_rds_dump_step_function` |

## Installation contexts

Three installation contexts are supported:

- **app-eks** — Application runs on an EKS cluster. Creates RDS, secrets, IAM roles, Kubernetes namespace. No ECS services.
- **app-ecs** — Application runs on ECS. Creates RDS, secrets, ECS services (backend, frontend), ALB rules, and DNS records.

Resource creation is controlled via **feature flags** (`create_*` variables), allowing the same module to serve all contexts.

> **Note:** Oracle RDS engine patch selection may use `data "external"` calling the AWS CLI to filter `describe-db-engine-versions` and pick the most recent `EngineVersion` containing `rur`.

## Example usage

The snippets below illustrate inputs for each context. In real usage, wire inputs from data sources, locals, or pipeline variables.

## EKS

### Production

Use this example for a **production EKS environment**.
Creates the RDS instance, S3 buckets (files/temp), Secrets Manager secrets, IAM roles for EKS service accounts, and Kubernetes namespace.
No ECS services are deployed — the application runs on EKS. Environment schedule is disabled (runs 24/7).

```hcl
module "app" {
  # Prefer pinning to a tag/commit.
  source = "git::https://github.com/augustovoigt/tofu-aws-application.git?ref=<tag-or-commit>"

  # General
  aws_account_id  = var.aws_account_id
  aws_region      = var.aws_region
  resource_prefix = var.resource_prefix
  environment     = var.environment

  # VPC / Security Groups
  vpc_id = local.regional_outputs.core.vpc_id

  # Optional: External access to RDS (e.g. VPN, on-premises)
  # create_sg_rds_external_access = true
  # rds_external_access_cidrs     = ["192.168.1.0/32"]

  # RDS (single instance)
  db_instance = [
    {
      # Parameter / option groups
      parameter_group_name = "oracle19-parameter-group"
      option_group_name    = "oracle19-option-group"

      # Instance sizing / storage
      instance_class    = "db.t3.medium"
      allocated_storage = 200
      storage_type      = "gp3"
      # Optional (when supported by storage_type)
      # iops               = 12000
      # storage_throughput = 500
      multi_az = false

      # Credentials (ignored when restoring from snapshot)
      username = "master"

      # Networking
      db_subnet_group_name = local.regional_outputs.core.db_private_subnet_group.name
      # Optional: Additional SGs to attach directly to RDS
      vpc_security_group_ids = concat(
        [local.regional_outputs.core.aws_database_security_group.id]
      )

      # Backups / snapshots
      # Optional: RDS snapshot ARN to restore from
      snapshot_identifier     = "arn:aws:rds:us-east-1:123456789012:snapshot:app-prod-snapshot-20260101"
      backup_retention_period = 7

      # Lifecycle / protection
      deletion_protection = true
      skip_final_snapshot = false

      # Monitoring
      monitoring_interval          = 0
      monitoring_role_arn          = local.global_outputs.core.iam_roles.rds_enhanced_monitoring.arn
      performance_insights_enabled = false

      # IAM associations
      db_instance_role_associations = {
        S3_INTEGRATION = local.global_outputs.core.iam_roles.rds_s3_integration.arn
      }
    }
  ]

  # IAM
  oidc_provider_arn                   = module.get_platform_states.eks.oidc.provider_arn
  create_iam_role_eks_service_account = true

  # Secrets Manager
  oracle_rotation_lambda_arn = local.vpc_scoped_outputs.core.lambda_secretsmanager_rds_oracle_password_rotation.lambda_secretsmanager_rds_oracle_password_rotation.lambda_function_arn

  # Kubernetes
  create_kubernetes_resources = true

  # Elasticache Valkey
  valkey_endpoint = local.vpc_scoped_outputs.core.elasticache_valkey.replication_group_primary_endpoint_address

  # Environment Schedule
  # Disabled for production (runs 24/7). Enable start_stop for non-prod.
  # environment_schedule = {
  #   timezone   = "UTC"
  #   start_stop = {
  #     start = { schedule_expression = "cron(0 8 ? * MON-FRI *)" }
  #     stop  = { schedule_expression = "cron(0 20 ? * MON-FRI *)" }
  #   }
  # }

  # Lambdas
  lambda_rds_oracle_execute_sql_statements    = local.vpc_scoped_outputs.core.lambda_rds_oracle_execute_sql_statements.lambda_rds_oracle_execute_sql_statements.lambda_function_name
  lambda_rds_oracle_update_users_credentials  = local.vpc_scoped_outputs.core.lambda_rds_oracle_update_users_credentials.lambda_rds_oracle_update_users_credentials.lambda_function_name

  # S3
  # enabled only in the production environment
  create_bucket_files = true
  create_bucket_temp  = true

  # Tags
  default_tags = local.default_tags
}
```

### Non-production

Use this example for a **non-production EKS environment** (e.g. `qa`, `staging`).
Similar to the prod example but with environment schedule (start/stop) enabled, the RDS dump step-function Lambda for database replication from production, and S3 buckets disabled (they live only in production).

```hcl
module "app" {
  # Prefer pinning to a tag/commit.
  source = "git::https://github.com/augustovoigt/tofu-aws-application.git?ref=<tag-or-commit>"

  # General
  aws_account_id  = var.aws_account_id
  aws_region      = var.aws_region
  resource_prefix = var.resource_prefix
  environment     = var.environment

  # VPC / Security Groups
  vpc_id = local.regional_outputs.core.vpc_id

  # Optional: External access to RDS (e.g. VPN, on-premises)
  # create_sg_rds_external_access = true
  # rds_external_access_cidrs     = ["192.168.1.0/32"]

  # RDS (single instance)
  db_instance = [
    {
      # Parameter / option groups
      parameter_group_name = "oracle19-parameter-group"
      option_group_name    = "oracle19-option-group"

      # Instance sizing / storage
      instance_class    = "db.t3.medium"
      allocated_storage = 200
      storage_type      = "gp3"
      # Optional (when supported by storage_type)
      # iops               = 12000
      # storage_throughput = 500
      multi_az = false

      # Credentials (ignored when restoring from snapshot)
      username = "master"

      # Networking
      db_subnet_group_name = local.regional_outputs.core.db_private_subnet_group.name
      # Optional: Additional SGs to attach directly to RDS
      vpc_security_group_ids = concat(
        [local.regional_outputs.core.aws_database_security_group.id]
      )

      # Backups / snapshots
      # Optional: RDS snapshot ARN to restore from
      snapshot_identifier     = "arn:aws:rds:us-east-1:123456789012:snapshot:app-prod-snapshot-20260101"
      backup_retention_period = 7

      # Lifecycle / protection
      deletion_protection = false
      skip_final_snapshot = true

      # Monitoring
      monitoring_interval          = 0
      monitoring_role_arn          = local.global_outputs.core.iam_roles.rds_enhanced_monitoring.arn
      performance_insights_enabled = false

      # IAM associations
      db_instance_role_associations = {
        S3_INTEGRATION = local.global_outputs.core.iam_roles.rds_s3_integration.arn
      }
    }
  ]

  # IAM
  oidc_provider_arn                   = module.get_platform_states.eks.oidc.provider_arn
  create_iam_role_eks_service_account = true

  # Secrets Manager
  oracle_rotation_lambda_arn = local.vpc_scoped_outputs.core.lambda_secretsmanager_rds_oracle_password_rotation.lambda_secretsmanager_rds_oracle_password_rotation.lambda_function_arn

  # Kubernetes
  create_kubernetes_resources = true

  # Elasticache Valkey
  valkey_endpoint = local.vpc_scoped_outputs.core.elasticache_valkey.replication_group_primary_endpoint_address

  # Environment Schedule
  environment_schedule = {
    timezone   = "UTC"
    start_stop = {
      start = { schedule_expression = "cron(0 8 ? * MON-FRI *)" }
      stop  = { schedule_expression = "cron(0 20 ? * MON-FRI *)" }
    }
  }

  # Lambdas
  lambda_rds_start_stop_instance_function_arn = local.regional_outputs.core.lambda_rds_start_stop_instance.lambda_rds_start_stop_instance.lambda_function_arn
  lambda_rds_oracle_execute_sql_statements    = local.vpc_scoped_outputs.core.lambda_rds_oracle_execute_sql_statements.lambda_rds_oracle_execute_sql_statements.lambda_function_name
  lambda_rds_oracle_update_users_credentials  = local.vpc_scoped_outputs.core.lambda_rds_oracle_update_users_credentials.lambda_rds_oracle_update_users_credentials.lambda_function_name

  # Dump
  create_lambda_rds_dump_step_function       = true
  step_functions_rds_dump_state_machine_arn  = local.vpc_scoped_outputs.core.step_functions.dump_rds.state_machine_arn
  lambda_rds_dump_sql_updates                = "SELECT 1 FROM dual;"

  # Tags
  default_tags = local.default_tags
}
```

## ECS

### Production

Use this example for a **production ECS environment**.
Creates the RDS instance, ECS services (backend, frontend), ALB listener rules, Route53 DNS records, S3 buckets, and Valkey integration.
All ECS services are configured with autoscaling.

```hcl
module "app" {
  # Prefer pinning to a tag/commit.
  source = "git::https://github.com/augustovoigt/tofu-aws-application.git?ref=<tag-or-commit>"

  # General
  aws_account_id  = var.aws_account_id
  aws_region      = var.aws_region
  resource_prefix = var.resource_prefix
  environment     = var.environment

  # VPC / Security Groups
  vpc_id = local.regional_outputs.core.vpc_id

  # Optional: External access to RDS (e.g. VPN, on-premises)
  # create_sg_rds_external_access = true
  # rds_external_access_cidrs     = ["192.168.1.0/32"]

  # DNS
  route53_subdomain = local.regional_outputs.route53_domain.public_zones[var.resource_prefix].subdomain

  # Route53 ALIAS records
  public_route53_zone = {
    zone_id      = local.regional_outputs.route53_domain.public_zones[var.resource_prefix].zone_id
    alb_dns_name = local.vpc_scoped_outputs.core.alb_dns_name["public"]
    alb_zone_id  = local.vpc_scoped_outputs.core.alb_zone_id["public"]
  }

  internal_route53_zone = {
    zone_id      = local.regional_outputs.route53_domain.private_zones[var.resource_prefix].zone_id
    alb_dns_name = local.vpc_scoped_outputs.core.alb_dns_name["internal"]
    alb_zone_id  = local.vpc_scoped_outputs.core.alb_zone_id["internal"]
  }

  # Example: public zone pointing to internal ALB
  # public_route53_zone = {
  #   zone_id      = local.regional_outputs.route53_domain.public_zones[var.resource_prefix].zone_id
  #   alb_dns_name = local.vpc_scoped_outputs.core.alb_dns_name["internal"]
  #   alb_zone_id  = local.vpc_scoped_outputs.core.alb_zone_id["internal"]
  # }

  # RDS (single instance)
  db_instance = [
    {
      # Parameter / option groups
      parameter_group_name = "pg-oracle-se2-19-t3-medium"
      option_group_name    = "og-oracle-se2-19"

      # Instance sizing / storage
      instance_class    = "db.t3.medium"
      allocated_storage = 220
      storage_type      = "gp3"
      # Optional (when supported by storage_type)
      # iops               = 12000
      # storage_throughput = 500
      multi_az = false

      # Credentials (ignored when restoring from snapshot)
      username = "master"

      # Networking
      db_subnet_group_name = local.regional_outputs.core.db_private_subnet_group.name
      # Optional: Additional SGs to attach directly to RDS
      vpc_security_group_ids = concat(
        [local.regional_outputs.core.aws_database_security_group.id]
      )

      # Backups / snapshots
      # Optional: RDS snapshot ARN to restore from
      snapshot_identifier     = "arn:aws:rds:us-east-1:123456789012:snapshot:app-prod-snapshot-20260101"
      backup_retention_period = 7

      # Lifecycle / protection
      deletion_protection = false
      skip_final_snapshot = false

      # Monitoring
      monitoring_interval          = 0
      monitoring_role_arn          = local.global_outputs.core.iam_roles.rds_enhanced_monitoring.arn
      performance_insights_enabled = false

      # IAM associations
      db_instance_role_associations = {
        S3_INTEGRATION = local.global_outputs.core.iam_roles.rds_s3_integration.arn
      }
    }
  ]

  # ECS
  create_ecs_services              = true
  cluster_arn                      = local.vpc_scoped_outputs.core.ecs_cluster_arn
  service_connect_namespace_arn    = local.vpc_scoped_outputs.core.ecs_cluster_cloud_map_namespace_arn
  cloud_map_namespace_id           = local.vpc_scoped_outputs.core.ecs_cluster_cloud_map_namespace_id
  private_subnet_ids               = local.regional_outputs.core.private_subnets
  alb_internal_security_group_id   = local.vpc_scoped_outputs.core.alb_security_group_id["internal"]
  alb_public_security_group_id     = local.vpc_scoped_outputs.core.alb_security_group_id["public"]

  # ECS locale defaults
  ecs_timezone = "UTC"
  ecs_region   = "US"
  ecs_language = "en"

  ecs_app_backend = {
    image                    = "1.0.0"
    desired_count            = 2
    autoscaling_min_capacity = 2
    autoscaling_max_capacity = 10

    # Default uses spot instances. To use on-demand instead:
    # capacity_provider_strategy = {
    #   on_demand = { capacity_provider = "on_demand", weight = 1, base = 1 }
    # }
    # cloudwatch_log_group_retention_in_days = 7
  }

  ecs_app_frontend = {
    image                    = "1.0.0"
    desired_count            = 2
    autoscaling_min_capacity = 2
    autoscaling_max_capacity = 10

    # Default uses spot instances. To use on-demand instead:
    # capacity_provider_strategy = {
    #   on_demand = { capacity_provider = "on_demand", weight = 1, base = 1 }
    # }
    # cloudwatch_log_group_retention_in_days = 7
  }

  # ALB Listener Rules
  #alb_internal_https_listener_arn = local.vpc_scoped_outputs.core.alb_listener_arn["internal"]["https"]
  alb_public_https_listener_arn = local.vpc_scoped_outputs.core.alb_listener_arn["public"]["https"]

  # Secrets Manager
  # Optional: set oracle_rotation_lambda_arn to enable automatic rotation
  # for the default RDS user secrets. When omitted, the secrets are still created.

  # Elasticache Valkey
  valkey_endpoint          = local.vpc_scoped_outputs.core.elasticache_valkey.replication_group_primary_endpoint_address
  valkey_security_group_id = local.vpc_scoped_outputs.core.elasticache_valkey.security_group_id

  # Lambdas
  lambda_rds_start_stop_instance_function_arn = local.regional_outputs.core.lambda_rds_start_stop_instance.lambda_rds_start_stop_instance.lambda_function_arn
  lambda_rds_oracle_execute_sql_statements   = local.vpc_scoped_outputs.core.lambda_rds_oracle_execute_sql_statements.lambda_rds_oracle_execute_sql_statements.lambda_function_name
  lambda_rds_oracle_update_users_credentials = local.vpc_scoped_outputs.core.lambda_rds_oracle_update_users_credentials.lambda_rds_oracle_update_users_credentials.lambda_function_name

  # S3
  # enabled only in the production environment
  create_bucket_files = true
  create_bucket_temp  = true

  # Tags
  default_tags = local.default_tags
}
```

### Non-production

Use this example for a **non-production ECS environment** (e.g. `qa`, `staging`).
Same as the ECS prod example but with environment schedule enabled, the RDS dump step-function Lambda for database replication from production, and S3 buckets disabled.

```hcl
module "app" {
  # Prefer pinning to a tag/commit.
  source = "git::https://github.com/augustovoigt/tofu-aws-application.git?ref=<tag-or-commit>"

  # General
  aws_account_id  = var.aws_account_id
  aws_region      = var.aws_region
  resource_prefix = var.resource_prefix
  environment     = var.environment

  # VPC / Security Groups
  vpc_id = local.regional_outputs.core.vpc_id

  # Optional: External access to RDS (e.g. VPN, on-premises)
  # create_sg_rds_external_access = true
  # rds_external_access_cidrs     = ["192.168.1.0/32"]

  # DNS
  route53_subdomain = local.regional_outputs.route53_domain.public_zones[var.resource_prefix].subdomain

  # Route53 ALIAS records
  public_route53_zone = {
    zone_id      = local.regional_outputs.route53_domain.public_zones[var.resource_prefix].zone_id
    alb_dns_name = local.vpc_scoped_outputs.core.alb_dns_name["public"]
    alb_zone_id  = local.vpc_scoped_outputs.core.alb_zone_id["public"]
  }

  internal_route53_zone = {
    zone_id      = local.regional_outputs.route53_domain.private_zones[var.resource_prefix].zone_id
    alb_dns_name = local.vpc_scoped_outputs.core.alb_dns_name["internal"]
    alb_zone_id  = local.vpc_scoped_outputs.core.alb_zone_id["internal"]
  }

  # RDS (single instance)
  db_instance = [
    {
      # Parameter / option groups
      parameter_group_name = "pg-oracle-se2-19-t3-medium"
      option_group_name    = "og-oracle-se2-19"

      # Instance sizing / storage
      instance_class    = "db.t3.medium"
      allocated_storage = 220
      storage_type      = "gp3"
      # Optional (when supported by storage_type)
      # iops               = 12000
      # storage_throughput = 500
      multi_az = false

      # Credentials (ignored when restoring from snapshot)
      username = "master"

      # Networking
      db_subnet_group_name = local.regional_outputs.core.db_private_subnet_group.name
      # Optional: Additional SGs to attach directly to RDS
      vpc_security_group_ids = concat(
        [local.regional_outputs.core.aws_database_security_group.id]
      )

      # Backups / snapshots
      # Optional: RDS snapshot ARN to restore from
      snapshot_identifier     = "arn:aws:rds:us-east-1:123456789012:snapshot:app-test-snapshot-20260101"
      backup_retention_period = 7

      # Lifecycle / protection
      deletion_protection = false
      skip_final_snapshot = true

      # Monitoring
      monitoring_interval          = 0
      monitoring_role_arn          = local.global_outputs.core.iam_roles.rds_enhanced_monitoring.arn
      performance_insights_enabled = false

      # IAM associations
      db_instance_role_associations = {
        S3_INTEGRATION = local.global_outputs.core.iam_roles.rds_s3_integration.arn
      }
    }
  ]

  # ECS
  create_ecs_services              = true
  cluster_arn                      = local.vpc_scoped_outputs.core.ecs_cluster_arn
  cloud_map_namespace_id           = local.vpc_scoped_outputs.core.ecs_cluster_cloud_map_namespace_id
  private_subnet_ids               = local.regional_outputs.core.private_subnets
  alb_internal_security_group_id   = local.vpc_scoped_outputs.core.alb_security_group_id["internal"]
  alb_public_security_group_id     = local.vpc_scoped_outputs.core.alb_security_group_id["public"]

  # ECS locale defaults
  ecs_timezone = "UTC"
  ecs_region   = "US"
  ecs_language = "en"

  ecs_app_backend = {
    image                    = "1.0.0"
    desired_count            = 2
    autoscaling_min_capacity = 2
    autoscaling_max_capacity = 10

    # Default uses spot instances. To use on-demand instead:
    # capacity_provider_strategy = {
    #   on_demand = { capacity_provider = "on_demand", weight = 1, base = 1 }
    # }
    # cloudwatch_log_group_retention_in_days = 7
  }

  ecs_app_frontend = {
    image                    = "1.0.0"
    desired_count            = 2
    autoscaling_min_capacity = 2
    autoscaling_max_capacity = 10

    # Default uses spot instances. To use on-demand instead:
    # capacity_provider_strategy = {
    #   on_demand = { capacity_provider = "on_demand", weight = 1, base = 1 }
    # }
    # cloudwatch_log_group_retention_in_days = 7
  }

  # ALB Listener Rules
  #alb_internal_https_listener_arn = local.vpc_scoped_outputs.core.alb_listener_arn["internal"]["https"]
  alb_public_https_listener_arn = local.vpc_scoped_outputs.core.alb_listener_arn["public"]["https"]

  # Elasticache Valkey
  valkey_endpoint          = local.vpc_scoped_outputs.core.elasticache_valkey.replication_group_primary_endpoint_address
  valkey_security_group_id = local.vpc_scoped_outputs.core.elasticache_valkey.security_group_id

  # Environment Schedule
  environment_schedule = {
    timezone   = "UTC"
    start_stop = {
      start = { schedule_expression = "cron(30 7 ? * MON-FRI *)" }
      stop  = { schedule_expression = "cron(0 18 ? * MON-FRI *)" }
    }
  }

  # Lambdas
  lambda_rds_start_stop_instance_function_arn = local.regional_outputs.core.lambda_rds_start_stop_instance.lambda_rds_start_stop_instance.lambda_function_arn
  lambda_rds_oracle_execute_sql_statements   = local.vpc_scoped_outputs.core.lambda_rds_oracle_execute_sql_statements.lambda_rds_oracle_execute_sql_statements.lambda_function_name
  lambda_rds_oracle_update_users_credentials = local.vpc_scoped_outputs.core.lambda_rds_oracle_update_users_credentials.lambda_rds_oracle_update_users_credentials.lambda_function_name

  # RDS dump step-function trigger Lambda (only for qa/staging environments)
  create_lambda_rds_dump_step_function      = true
  step_functions_rds_dump_state_machine_arn = local.vpc_scoped_outputs.core.step_functions.dump_rds.state_machine_arn
  #lambda_rds_dump_sql_updates = "SELECT 1 FROM dual;"

  # Tags
  default_tags = local.default_tags
}
```

### Replica environment

Use this example when creating a **replica environment**.
The RDS instance is created from a production snapshot, and the `lambda_rds_dump_step_function` is enabled so you can trigger a dump from production to this replica via the AWS Console whenever needed.
No ECS services are created in this context — only the database and the dump automation.

```hcl
module "app" {
  # Prefer pinning to a tag/commit.
  source = "git::https://github.com/augustovoigt/tofu-aws-application.git?ref=<tag-or-commit>"

  # General
  aws_account_id  = var.aws_account_id
  aws_region      = var.aws_region
  resource_prefix = var.resource_prefix
  environment     = var.environment

  # VPC / Security Groups
  vpc_id = local.regional_outputs.core.vpc_id

  # External access to RDS (e.g. VPN, on-premises)
  create_sg_rds_external_access = true
  rds_external_access_cidrs     = ["192.168.1.0/32"]

  # RDS (single instance — restored from production snapshot)
  db_instance = [
    {
      # Parameter / option groups
      parameter_group_name = "pg-oracle-se2-19-t3-medium"
      option_group_name    = "og-oracle-se2-19"

      # Instance sizing / storage
      instance_class    = "db.t3.medium"
      allocated_storage = 220
      storage_type      = "gp3"
      multi_az          = false

      # Credentials (ignored when restoring from snapshot)
      username = "master"

      # Networking
      db_subnet_group_name = local.regional_outputs.core.db_private_subnet_group.name
      vpc_security_group_ids = concat(
        [local.regional_outputs.core.aws_database_security_group.id]
      )

      # Backups / snapshots
      snapshot_identifier     = "arn:aws:rds:us-east-1:123456789012:snapshot:app-prod-snapshot-20260101"
      backup_retention_period = 7

      # Lifecycle / protection
      deletion_protection = false
      skip_final_snapshot = true

      # Monitoring
      monitoring_interval          = 0
      monitoring_role_arn          = local.global_outputs.core.iam_roles.rds_enhanced_monitoring.arn
      performance_insights_enabled = false

      # IAM associations
      db_instance_role_associations = {
        S3_INTEGRATION = local.global_outputs.core.iam_roles.rds_s3_integration.arn
      }
    }
  ]

  # Elasticache Valkey
  valkey_endpoint = local.vpc_scoped_outputs.core.elasticache_valkey.replication_group_primary_endpoint_address

  # Lambdas
  lambda_rds_start_stop_instance_function_arn = local.regional_outputs.core.lambda_rds_start_stop_instance.lambda_rds_start_stop_instance.lambda_function_arn
  lambda_rds_oracle_execute_sql_statements   = local.vpc_scoped_outputs.core.lambda_rds_oracle_execute_sql_statements.lambda_rds_oracle_execute_sql_statements.lambda_function_name
  lambda_rds_oracle_update_users_credentials = local.vpc_scoped_outputs.core.lambda_rds_oracle_update_users_credentials.lambda_rds_oracle_update_users_credentials.lambda_function_name

  # RDS dump step-function trigger Lambda
  # Creates a Lambda that can be invoked from the AWS Console to perform a dump from production env
  create_lambda_rds_dump_step_function      = true
  step_functions_rds_dump_state_machine_arn = local.vpc_scoped_outputs.core.step_functions.dump_rds.state_machine_arn
  lambda_rds_dump_sql_updates               = "SELECT 1 FROM dual;"

  # Optional: schedule automatic daily dump from production (e.g. every day at 3 AM)
  # environment_schedule = {
  #   timezone = "UTC"
  #   rds_dump = { schedule_expression = "cron(0 3 ? * * *)" }
  # }

  # Tags
  default_tags = local.default_tags
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.11 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |
| <a name="requirement_external"></a> [external](#requirement\_external) | ~> 2.3.5 |
| <a name="requirement_random"></a> [random](#requirement\_random) | ~> 3.8.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.34.0 |
| <a name="provider_external"></a> [external](#provider\_external) | 2.3.5 |
| <a name="provider_kubernetes"></a> [kubernetes](#provider\_kubernetes) | 3.0.1 |
| <a name="provider_random"></a> [random](#provider\_random) | 3.8.1 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_ecs_service"></a> [ecs\_service](#module\_ecs\_service) | terraform-aws-modules/ecs/aws//modules/service | n/a |
| <a name="module_iam_roles"></a> [iam\_roles](#module\_iam\_roles) | terraform-aws-modules/iam/aws//modules/iam-role | 6.4.0 |
| <a name="module_lambda_rds_dump_step_function"></a> [lambda\_rds\_dump\_step\_function](#module\_lambda\_rds\_dump\_step\_function) | ./modules/lambdas/lambda-rds-dump-step-function | n/a |
| <a name="module_rds"></a> [rds](#module\_rds) | terraform-aws-modules/rds/aws | 7.1.0 |
| <a name="module_s3_buckets"></a> [s3\_buckets](#module\_s3\_buckets) | terraform-aws-modules/s3-bucket/aws | 5.10.0 |
| <a name="module_schedulesets"></a> [schedulesets](#module\_schedulesets) | terraform-aws-modules/eventbridge/aws | 4.3.0 |
| <a name="module_secrets"></a> [secrets](#module\_secrets) | terraform-aws-modules/secrets-manager/aws | 2.1.0 |
| <a name="module_security_groups"></a> [security\_groups](#module\_security\_groups) | terraform-aws-modules/security-group/aws | 5.3.1 |
| <a name="module_ssm_parameters"></a> [ssm\_parameters](#module\_ssm\_parameters) | terraform-aws-modules/ssm-parameter/aws | 2.1.0 |
| <a name="module_app_namespace"></a> [app\_namespace](#module\_app\_namespace) | git::https://github.com/augustovoigt/tofu-aws-modules.git//modules/kubernetes/namespace/ | v0.1.0 |

## Resources

| Name | Type |
|------|------|
| [aws_lambda_invocation.invoke_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_invocation) | resource |
| [aws_lb_listener_rule.app_backend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_listener_rule.app_frontend](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.app_backend_internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.app_backend_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.app_frontend_internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group.app_frontend_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_route53_record.app_frontend_internal](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_route53_record.app_frontend_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_secretsmanager_secret_rotation.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/secretsmanager_secret_rotation) | resource |
| [aws_vpc_security_group_ingress_rule.rds_primary_from_ecs_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.valkey_from_ecs_services](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [kubernetes_config_map_v1.app_config](https://registry.terraform.io/providers/hashicorp/kubernetes/latest/docs/resources/config_map_v1) | resource |
| [random_password.db_instance_master_credentials](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [random_password.rds_app_user_password](https://registry.terraform.io/providers/hashicorp/random/latest/docs/resources/password) | resource |
| [external_external.db_instance_engine_version](https://registry.terraform.io/providers/hashicorp/external/latest/docs/data-sources/external) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_additional_s3_buckets"></a> [additional\_s3\_buckets](#input\_additional\_s3\_buckets) | Additional buckets to create. Map of bucket\_key -> bucket\_name (merged on top of defaults). | `map(string)` | `{}` | no |
| <a name="input_alb_additional_listener_rules"></a> [alb\_additional\_listener\_rules](#input\_alb\_additional\_listener\_rules) | Additional ALB listener rules beyond the module defaults. Keys are rule names, values define listener\_arn, priority, target service, target\_group\_arn, and path conditions. Host is auto-generated as app-{environment}.{subdomain}. | <pre>map(object({<br/>    listener_arn     = string<br/>    priority         = number<br/>    service          = string<br/>    target_group_arn = string<br/>    paths            = optional(list(string), ["/*"])<br/>  }))</pre> | `{}` | no |
| <a name="input_alb_internal_https_listener_arn"></a> [alb\_internal\_https\_listener\_arn](#input\_alb\_internal\_https\_listener\_arn) | ARN of the HTTPS listener on the internal ALB. When set, creates internal target groups and default listener rules for app-frontend and app-backend. | `string` | `""` | no |
| <a name="input_alb_internal_security_group_id"></a> [alb\_internal\_security\_group\_id](#input\_alb\_internal\_security\_group\_id) | Security group ID of the internal ALB. Used to allow health check traffic from the internal ALB to ECS services. | `string` | `""` | no |
| <a name="input_alb_public_https_listener_arn"></a> [alb\_public\_https\_listener\_arn](#input\_alb\_public\_https\_listener\_arn) | ARN of the HTTPS listener on the public ALB. When set, creates public target groups and default listener rules for app-frontend and app-backend. | `string` | `""` | no |
| <a name="input_alb_public_security_group_id"></a> [alb\_public\_security\_group\_id](#input\_alb\_public\_security\_group\_id) | Security group ID of the public ALB. Used to allow health check traffic from the public ALB to ECS services. | `string` | `""` | no |
| <a name="input_aws_account_id"></a> [aws\_account\_id](#input\_aws\_account\_id) | AWS Account ID for resource provisioning. | `string` | n/a | yes |
| <a name="input_aws_region"></a> [aws\_region](#input\_aws\_region) | AWS Region where resources will be provisioned. | `string` | n/a | yes |
| <a name="input_cloud_map_namespace_id"></a> [cloud\_map\_namespace\_id](#input\_cloud\_map\_namespace\_id) | ID of the Cloud Map private DNS namespace used for ECS Service Discovery (Route 53 DNS-based). | `string` | `null` | no |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | Optional ECS cluster ARN used by ECS services. Must be set when create\_ecs\_services is true. | `string` | `null` | no |
| <a name="input_create_bucket_files"></a> [create\_bucket\_files](#input\_create\_bucket\_files) | Whether to create the default 'files' bucket for the application. | `bool` | `false` | no |
| <a name="input_create_bucket_temp"></a> [create\_bucket\_temp](#input\_create\_bucket\_temp) | Whether to create the default 'temp' bucket for the application. | `bool` | `false` | no |
| <a name="input_create_ecs_services"></a> [create\_ecs\_services](#input\_create\_ecs\_services) | Whether to create the ECS services defined in ecs-services.tf. | `bool` | `false` | no |
| <a name="input_create_iam_role_eks_service_account"></a> [create\_iam\_role\_eks\_service\_account](#input\_create\_iam\_role\_eks\_service\_account) | Whether to create the default EKS service account IAM role (eks\_service\_account). | `bool` | `false` | no |
| <a name="input_create_kubernetes_resources"></a> [create\_kubernetes\_resources](#input\_create\_kubernetes\_resources) | Whether to create Kubernetes resources (namespace, config map, etc.). | `bool` | `false` | no |
| <a name="input_create_lambda_rds_dump_step_function"></a> [create\_lambda\_rds\_dump\_step\_function](#input\_create\_lambda\_rds\_dump\_step\_function) | Whether to create the RDS dump step-function trigger Lambda. | `bool` | `false` | no |
| <a name="input_create_sg_rds_external_access"></a> [create\_sg\_rds\_external\_access](#input\_create\_sg\_rds\_external\_access) | Whether to create a security group that allows external IP access to the RDS database on port 1521. | `bool` | `false` | no |
| <a name="input_create_sg_rds_primary"></a> [create\_sg\_rds\_primary](#input\_create\_sg\_rds\_primary) | Whether to create the default primary RDS security group (rds\_primary). | `bool` | `true` | no |
| <a name="input_db_instance"></a> [db\_instance](#input\_db\_instance) | Configuration object for the RDS instance. | <pre>list(object({<br/>    # Engine<br/>    engine         = optional(string, "oracle-se2")<br/>    engine_version = optional(string, "19")<br/>    license_model  = optional(string, "license-included")<br/><br/>    # Parameter / option groups<br/>    parameter_group_name = string<br/>    option_group_name    = string<br/><br/>    # Instance sizing / storage<br/>    instance_class     = string<br/>    allocated_storage  = number<br/>    storage_type       = string<br/>    iops               = optional(number)<br/>    storage_throughput = optional(number)<br/>    multi_az           = bool<br/><br/>    # Minor upgrades / certificates<br/>    auto_minor_version_upgrade = optional(bool, true)<br/>    ca_cert_identifier         = optional(string, "")<br/>    kms_key_id                 = optional(string)<br/><br/>    # Credentials (ignored when restoring from snapshot)<br/>    username = optional(string, "master")<br/><br/>    # Networking<br/>    db_subnet_group_name   = string<br/>    publicly_accessible    = optional(bool, false)<br/>    vpc_security_group_ids = optional(list(string), [])<br/><br/>    # Backups / snapshots<br/>    snapshot_identifier     = optional(string, "")<br/>    backup_retention_period = optional(number, 0)<br/>    copy_tags_to_snapshot   = optional(bool, false)<br/><br/>    # Lifecycle / protection<br/>    deletion_protection = bool<br/>    skip_final_snapshot = optional(bool, false)<br/><br/>    # Monitoring<br/>    monitoring_interval = optional(number, 0)<br/>    monitoring_role_arn = string<br/><br/>    # Performance Insights<br/>    performance_insights_enabled = optional(bool, false)<br/><br/>    # IAM associations<br/>    # map(feature_name => role_arn)<br/>    db_instance_role_associations = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_default_tags"></a> [default\_tags](#input\_default\_tags) | Default tags applied to all resources. | `map(string)` | `{}` | no |
| <a name="input_ecs_app_backend"></a> [ecs\_app\_backend](#input\_ecs\_app\_backend) | Configuration overrides for the default app-backend ECS service settings. | <pre>object({<br/>    name                     = optional(string, "app-backend")<br/>    repository               = optional(string, "123456789012.dkr.ecr.us-east-1.amazonaws.com/app/backend")<br/>    image                    = optional(string, "1.0.0")<br/>    cpu                      = optional(number, 1024)<br/>    memory                   = optional(number, 3800)<br/>    enable_autoscaling       = optional(bool, true)<br/>    desired_count            = optional(number, 0)<br/>    autoscaling_min_capacity = optional(number, 0)<br/>    autoscaling_max_capacity = optional(number, 0)<br/><br/>    requires_compatibilities = optional(list(string), ["MANAGED_INSTANCES"])<br/><br/>    capacity_provider_strategy = optional(map(object({<br/>      capacity_provider = string<br/>      weight            = optional(number, 0)<br/>      base              = optional(number, 0)<br/>      })), {<br/>      spot = {<br/>        capacity_provider = "spot"<br/>        weight            = 1<br/>      }<br/>    })<br/><br/>    autoscaling_policies = optional(any, {<br/>      cpu = {<br/>        policy_type = "TargetTrackingScaling"<br/>        target_tracking_scaling_policy_configuration = {<br/>          predefined_metric_specification = {<br/>            predefined_metric_type = "ECSServiceAverageCPUUtilization"<br/>          }<br/>          target_value       = 70<br/>          scale_in_cooldown  = 300<br/>          scale_out_cooldown = 60<br/>        }<br/>      }<br/>    })<br/><br/>    deployment_circuit_breaker = optional(object({<br/>      enable   = optional(bool, true)<br/>      rollback = optional(bool, true)<br/>      }), {<br/>      enable   = true<br/>      rollback = true<br/>    })<br/><br/>    ordered_placement_strategy = optional(list(object({<br/>      type  = string<br/>      field = string<br/>    })), [])<br/><br/>    availability_zone_rebalancing = optional(string, "DISABLED")<br/>    wait_for_steady_state         = optional(bool, true)<br/><br/>    ssl_enabled = optional(bool, false)<br/><br/>    cloudwatch_log_group_retention_in_days = optional(number, 7)<br/>  })</pre> | `{}` | no |
| <a name="input_ecs_app_frontend"></a> [ecs\_app\_frontend](#input\_ecs\_app\_frontend) | Configuration overrides for the default app-frontend ECS service settings. | <pre>object({<br/>    name                     = optional(string, "app-frontend")<br/>    repository               = optional(string, "123456789012.dkr.ecr.us-east-1.amazonaws.com/app/frontend")<br/>    image                    = optional(string, "1.0.0-NGINX")<br/>    cpu                      = optional(number, 512)<br/>    memory                   = optional(number, 256)<br/>    enable_autoscaling       = optional(bool, true)<br/>    desired_count            = optional(number, 0)<br/>    autoscaling_min_capacity = optional(number, 0)<br/>    autoscaling_max_capacity = optional(number, 0)<br/><br/>    requires_compatibilities = optional(list(string), ["MANAGED_INSTANCES"])<br/><br/>    capacity_provider_strategy = optional(map(object({<br/>      capacity_provider = string<br/>      weight            = optional(number, 0)<br/>      base              = optional(number, 0)<br/>      })), {<br/>      spot = {<br/>        capacity_provider = "spot"<br/>        weight            = 1<br/>      }<br/>    })<br/><br/>    autoscaling_policies = optional(any, {<br/>      cpu = {<br/>        policy_type = "TargetTrackingScaling"<br/>        target_tracking_scaling_policy_configuration = {<br/>          predefined_metric_specification = {<br/>            predefined_metric_type = "ECSServiceAverageCPUUtilization"<br/>          }<br/>          target_value       = 70<br/>          scale_in_cooldown  = 300<br/>          scale_out_cooldown = 60<br/>        }<br/>      }<br/>    })<br/><br/>    deployment_circuit_breaker = optional(object({<br/>      enable   = optional(bool, true)<br/>      rollback = optional(bool, true)<br/>      }), {<br/>      enable   = true<br/>      rollback = true<br/>    })<br/><br/>    ordered_placement_strategy = optional(list(object({<br/>      type  = string<br/>      field = string<br/>    })), [])<br/><br/>    availability_zone_rebalancing = optional(string, "DISABLED")<br/>    wait_for_steady_state         = optional(bool, true)<br/><br/>    ssl_enabled = optional(bool, false)<br/><br/>    cloudwatch_log_group_retention_in_days = optional(number, 7)<br/>  })</pre> | `{}` | no |
| <a name="input_ecs_language"></a> [ecs\_language](#input\_ecs\_language) | Default LANGUAGE value injected into ECS services. | `string` | `"en"` | no |
| <a name="input_ecs_region"></a> [ecs\_region](#input\_ecs\_region) | Default REGION value injected into ECS services. | `string` | `"US"` | no |
| <a name="input_ecs_timezone"></a> [ecs\_timezone](#input\_ecs\_timezone) | Default TIMEZONE value injected into ECS services. | `string` | `"UTC"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment to be deployed (e.g., prod, qa). Must be at most 8 characters. | `string` | n/a | yes |
| <a name="input_environment_schedule"></a> [environment\_schedule](#input\_environment\_schedule) | Generic start/stop schedule for the environment. Drives both RDS EventBridge schedules and ECS autoscaling scheduled actions from a single source of truth. | <pre>object({<br/>    enabled              = optional(bool, false)<br/>    timezone             = optional(string, "UTC")<br/>    start_offset_minutes = optional(number, 15)<br/>    start = object({<br/>      schedule_expression = string<br/>    })<br/>    stop = object({<br/>      schedule_expression = string<br/>    })<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "start": {<br/>    "schedule_expression": "cron(0 8 ? * MON-FRI *)"<br/>  },<br/>  "stop": {<br/>    "schedule_expression": "cron(0 20 ? * MON-FRI *)"<br/>  }<br/>}</pre> | no |
| <a name="input_eventbridge_schedulesets"></a> [eventbridge\_schedulesets](#input\_eventbridge\_schedulesets) | Additional EventBridge schedule sets to create. This map is merged on top of the default rds\_start\_stop\_instance set. | <pre>map(object({<br/>    create_bus           = optional(bool, false)<br/>    role_name            = optional(string)<br/>    attach_lambda_policy = optional(bool, false)<br/>    lambda_target_arns   = optional(list(string), [])<br/>    schedules = map(object({<br/>      description         = optional(string)<br/>      schedule_expression = string<br/>      timezone            = optional(string)<br/>      arn                 = optional(string)<br/>      input               = optional(string)<br/>    }))<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_iam_roles"></a> [iam\_roles](#input\_iam\_roles) | Additional IAM roles to create. This map is merged on top of the default eks\_service\_account role. | <pre>map(object({<br/>    name                      = string<br/>    use_name_prefix           = optional(bool, false)<br/>    trust_policy_permissions  = any<br/>    create_inline_policy      = optional(bool, false)<br/>    inline_policy_permissions = optional(any, {})<br/>    tags                      = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_internal_route53_zone"></a> [internal\_route53\_zone](#input\_internal\_route53\_zone) | Internal Route53 zone for creating ALIAS records. The alb\_dns\_name/alb\_zone\_id define which ALB the record points to (typically the internal ALB, but can be any). | <pre>object({<br/>    zone_id      = string<br/>    alb_dns_name = string<br/>    alb_zone_id  = string<br/>  })</pre> | `null` | no |
| <a name="input_lambda_rds_dump_schedule_expression"></a> [lambda\_rds\_dump\_schedule\_expression](#input\_lambda\_rds\_dump\_schedule\_expression) | EventBridge cron/rate expression to trigger the RDS dump Lambda on a schedule. When empty (default), no schedule is created and the Lambda can only be invoked manually via the AWS Console. | `string` | `""` | no |
| <a name="input_lambda_rds_dump_sql_updates"></a> [lambda\_rds\_dump\_sql\_updates](#input\_lambda\_rds\_dump\_sql\_updates) | SQL statements passed to the RDS dump automation Lambda. | `string` | `""` | no |
| <a name="input_lambda_rds_oracle_execute_sql_statements"></a> [lambda\_rds\_oracle\_execute\_sql\_statements](#input\_lambda\_rds\_oracle\_execute\_sql\_statements) | Lambda function name or ARN used to execute SQL statements against the Oracle RDS instance. | `string` | n/a | yes |
| <a name="input_lambda_rds_oracle_update_users_credentials"></a> [lambda\_rds\_oracle\_update\_users\_credentials](#input\_lambda\_rds\_oracle\_update\_users\_credentials) | Lambda function name or ARN used to update Oracle RDS user credentials. | `string` | n/a | yes |
| <a name="input_lambda_rds_start_stop_instance_function_arn"></a> [lambda\_rds\_start\_stop\_instance\_function\_arn](#input\_lambda\_rds\_start\_stop\_instance\_function\_arn) | The ARN of the Lambda function to start/stop RDS instance. Required when environment\_schedule.enabled is true. | `string` | `""` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | ARN OIDC provider EKS cluster. | `string` | `""` | no |
| <a name="input_oracle_rotation_lambda_arn"></a> [oracle\_rotation\_lambda\_arn](#input\_oracle\_rotation\_lambda\_arn) | Optional ARN of the Lambda function used for rotating Oracle RDS passwords. When unset, the module still creates the secrets but skips automatic rotation for the default RDS user secrets. | `string` | `""` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Private subnet IDs that can be used by internal resources. Required when create\_ecs\_services is true. | `list(string)` | `[]` | no |
| <a name="input_public_route53_zone"></a> [public\_route53\_zone](#input\_public\_route53\_zone) | Public Route53 zone for creating ALIAS records. The alb\_dns\_name/alb\_zone\_id define which ALB the record points to (e.g., public ALB, or internal ALB for private-facing public DNS). | <pre>object({<br/>    zone_id      = string<br/>    alb_dns_name = string<br/>    alb_zone_id  = string<br/>  })</pre> | `null` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | Public subnet IDs that can be used by public resources. | `list(string)` | `[]` | no |
| <a name="input_rds_external_access_cidrs"></a> [rds\_external\_access\_cidrs](#input\_rds\_external\_access\_cidrs) | List of CIDR blocks allowed to access the RDS database on port 1521 via the rds\_external\_access security group. Each entry must be in CIDR notation (e.g. 192.168.0.1/32). | `list(string)` | `[]` | no |
| <a name="input_rds_schema"></a> [rds\_schema](#input\_rds\_schema) | Schema name for the RDS database. | `string` | `"app"` | no |
| <a name="input_rds_users"></a> [rds\_users](#input\_rds\_users) | Map of RDS users and their Secrets Manager rotation settings. Rotation is enabled by default for all users. | <pre>map(object({<br/>    rotation_enabled                     = optional(bool, true)<br/>    rotation_schedule_expression_prod    = string<br/>    rotation_schedule_expression_nonprod = string<br/>  }))</pre> | <pre>{<br/>  "app": {<br/>    "rotation_enabled": true,<br/>    "rotation_schedule_expression_nonprod": "cron(0 11 ? 1/3 2L *)",<br/>    "rotation_schedule_expression_prod": "cron(0 07 ? 1/3 1L *)"<br/>  },<br/>  "consultant": {<br/>    "rotation_enabled": true,<br/>    "rotation_schedule_expression_nonprod": "cron(0 11 ? 1/3 2L *)",<br/>    "rotation_schedule_expression_prod": "cron(0 07 ? 1/3 1L *)"<br/>  },<br/>  "master": {<br/>    "rotation_enabled": true,<br/>    "rotation_schedule_expression_nonprod": "cron(0 11 ? 1/3 2L *)",<br/>    "rotation_schedule_expression_prod": "cron(0 07 ? 1/3 1L *)"<br/>  },<br/>  "monitoring": {<br/>    "rotation_enabled": true,<br/>    "rotation_schedule_expression_nonprod": "cron(0 11 ? 1/3 2L *)",<br/>    "rotation_schedule_expression_prod": "cron(0 07 ? 1/3 1L *)"<br/>  },<br/>  "readonly": {<br/>    "rotation_enabled": true,<br/>    "rotation_schedule_expression_nonprod": "cron(0 11 ? 1/3 2L *)",<br/>    "rotation_schedule_expression_prod": "cron(0 07 ? 1/3 1L *)"<br/>  },<br/>  "support": {<br/>    "rotation_enabled": true,<br/>    "rotation_schedule_expression_nonprod": "cron(0 11 ? * 2-6 *)",<br/>    "rotation_schedule_expression_prod": "cron(0 07 * * ? *)"<br/>  }<br/>}</pre> | no |
| <a name="input_resource_prefix"></a> [resource\_prefix](#input\_resource\_prefix) | Prefix that uniquely identifies this environment's resources. Needs to be unique per AWS (sub) account. | `string` | n/a | yes |
| <a name="input_route53_subdomain"></a> [route53\_subdomain](#input\_route53\_subdomain) | The fully qualified subdomain from the route53-domain module (e.g., 'lab.example.com'). Used to build ALB listener rule host headers as app-{resource\_prefix}.{subdomain}. | `string` | `""` | no |
| <a name="input_s3_attach_policy"></a> [s3\_attach\_policy](#input\_s3\_attach\_policy) | Whether to attach the default bucket policy (SSE enforcement + deny insecure transport). | `bool` | `true` | no |
| <a name="input_s3_bucket_policy_sse_algorithm"></a> [s3\_bucket\_policy\_sse\_algorithm](#input\_s3\_bucket\_policy\_sse\_algorithm) | SSE algorithm required by the default S3 policy via s3:x-amz-server-side-encryption (e.g., AES256 or aws:kms). | `string` | `"AES256"` | no |
| <a name="input_s3_bucket_tags"></a> [s3\_bucket\_tags](#input\_s3\_bucket\_tags) | Common tags applied to all buckets created by this stack. | `map(string)` | <pre>{<br/>  "Backup": "yes"<br/>}</pre> | no |
| <a name="input_s3_per_bucket_tags"></a> [s3\_per\_bucket\_tags](#input\_s3\_per\_bucket\_tags) | Optional extra tags per bucket key (merged on top of s3\_bucket\_tags). | `map(map(string))` | `{}` | no |
| <a name="input_s3_versioning_enabled"></a> [s3\_versioning\_enabled](#input\_s3\_versioning\_enabled) | Whether to enable versioning on all buckets created by this stack. | `bool` | `true` | no |
| <a name="input_secrets_manager_secrets"></a> [secrets\_manager\_secrets](#input\_secrets\_manager\_secrets) | Additional Secrets Manager secrets to create. This map is merged on top of the default RDS user secrets. | <pre>map(object({<br/>    name                    = string<br/>    description             = optional(string)<br/>    secret_string           = string<br/>    recovery_window_in_days = optional(number, 0)<br/>    ignore_secret_changes   = optional(bool, true)<br/>    kms_key_id              = optional(string)<br/>    tags                    = optional(map(string), {})<br/>    rotation = optional(object({<br/>      enabled             = optional(bool, false)<br/>      lambda_arn          = string<br/>      schedule_expression = string<br/>      duration            = optional(string, "1h")<br/>      rotate_immediately  = optional(bool, false)<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_security_groups"></a> [security\_groups](#input\_security\_groups) | Additional security groups to create. This map is merged on top of the default rds\_primary and ecs\_services groups. | <pre>map(object({<br/>    name            = string<br/>    description     = string<br/>    vpc_id          = string<br/>    use_name_prefix = optional(bool, false)<br/>    ingress_with_cidr_blocks = optional(list(object({<br/>      from_port   = number<br/>      to_port     = number<br/>      protocol    = string<br/>      description = optional(string)<br/>      cidr_blocks = string<br/>    })), [])<br/>    egress_with_cidr_blocks = optional(list(object({<br/>      from_port   = number<br/>      to_port     = number<br/>      protocol    = string<br/>      description = optional(string)<br/>      cidr_blocks = string<br/>    })), [])<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_ssm_parameters"></a> [ssm\_parameters](#input\_ssm\_parameters) | Additional SSM parameters to create. This map is merged on top of the default rds\_config parameter. | <pre>map(object({<br/>    name            = string<br/>    description     = optional(string)<br/>    type            = optional(string, "String")<br/>    value           = string<br/>    overwrite       = optional(bool, true)<br/>    tier            = optional(string)<br/>    key_id          = optional(string)<br/>    allowed_pattern = optional(string)<br/>    data_type       = optional(string)<br/>    tags            = optional(map(string), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_step_functions_rds_dump_state_machine_arn"></a> [step\_functions\_rds\_dump\_state\_machine\_arn](#input\_step\_functions\_rds\_dump\_state\_machine\_arn) | Step Functions state machine ARN used by the RDS dump automation Lambda. | `string` | `""` | no |
| <a name="input_valkey_endpoint"></a> [valkey\_endpoint](#input\_valkey\_endpoint) | Valkey endpoint URL for the application to connect to the Valkey service. | `string` | n/a | yes |
| <a name="input_valkey_security_group_id"></a> [valkey\_security\_group\_id](#input\_valkey\_security\_group\_id) | Security group ID of the existing Valkey cluster used to allow ingress from ECS services. | `string` | `null` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | The ID of the VPC where the security groups will be created. Value from state of main infra module. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_ecs_service_target_group_arns"></a> [ecs\_service\_target\_group\_arns](#output\_ecs\_service\_target\_group\_arns) | Map of ECS logical service name -> target group ARNs (internal and public). |
| <a name="output_ecs_services"></a> [ecs\_services](#output\_ecs\_services) | Map of ECS service key -> ECS service module outputs. |
| <a name="output_eventbridge_lambda_rds_start_stop_instance_schedule_ids"></a> [eventbridge\_lambda\_rds\_start\_stop\_instance\_schedule\_ids](#output\_eventbridge\_lambda\_rds\_start\_stop\_instance\_schedule\_ids) | IDs of the EventBridge schedules created. |
| <a name="output_eventbridge_rule_ids"></a> [eventbridge\_rule\_ids](#output\_eventbridge\_rule\_ids) | Map of scheduleset key -> EventBridge rule IDs map. |
| <a name="output_iam_roles"></a> [iam\_roles](#output\_iam\_roles) | Map of IAM role key -> IAM role info (includes default and additional roles). |
| <a name="output_rds"></a> [rds](#output\_rds) | Outputs from the RDS module (null when create\_rds=false) |
| <a name="output_secrets_manager_db_instance_user_credentials_arns"></a> [secrets\_manager\_db\_instance\_user\_credentials\_arns](#output\_secrets\_manager\_db\_instance\_user\_credentials\_arns) | ARNs of the secrets created for RDS users. |
| <a name="output_secrets_manager_secret_arns"></a> [secrets\_manager\_secret\_arns](#output\_secrets\_manager\_secret\_arns) | Map of secret key -> secret ARN (includes default and additional secrets). |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Map of security group key -> security group ID. |
| <a name="output_sg_rds_primary_id"></a> [sg\_rds\_primary\_id](#output\_sg\_rds\_primary\_id) | ID of the primary RDS security group. |
| <a name="output_ssm_parameter_arns"></a> [ssm\_parameter\_arns](#output\_ssm\_parameter\_arns) | Map of SSM parameter key -> parameter ARN (includes default and additional parameters). |
| <a name="output_ssm_parameter_names"></a> [ssm\_parameter\_names](#output\_ssm\_parameter\_names) | Map of SSM parameter key -> parameter name (includes default and additional parameters). |
<!-- END_TF_DOCS -->
