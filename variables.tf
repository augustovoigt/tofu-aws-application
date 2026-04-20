# General

variable "aws_region" {
  description = "AWS Region where resources will be provisioned."
  type        = string

  validation {
    condition     = length(trimspace(var.aws_region)) > 0
    error_message = "aws_region must be a non-empty string."
  }
}

variable "aws_account_id" {
  description = "AWS Account ID for resource provisioning."
  type        = string

  validation {
    condition     = length(trimspace(var.aws_account_id)) > 0
    error_message = "aws_account_id must be a non-empty string."
  }
}

variable "resource_prefix" {
  description = "Prefix uniquely identifies application environment resources. Needs to be unique per AWS (sub) account."
  type        = string

  validation {
    condition     = length(var.resource_prefix) <= 15
    error_message = "The resource_prefix value must be at most 15 characters long."
  }

  validation {
    condition     = length(trimspace(var.resource_prefix)) > 0
    error_message = "resource_prefix must be a non-empty string."
  }
}

variable "environment" {
  description = "Environment to be deployed (e.g., prod, qa). Must be at most 8 characters."
  type        = string

  validation {
    condition     = length(var.environment) <= 8
    error_message = "The environment value must be at most 8 characters long."
  }

  validation {
    condition     = length(trimspace(var.environment)) > 0
    error_message = "environment must be a non-empty string."
  }
}

variable "default_tags" {
  description = "Default tags applied to all resources."
  type        = map(string)
  default     = {}
}

# VPC

variable "vpc_id" {
  description = "The ID of the VPC where the security groups will be created. Value from state of main infra module."
  type        = string

  validation {
    condition     = length(trimspace(var.vpc_id)) > 0
    error_message = "vpc_id must be a non-empty string."
  }
}

variable "private_subnet_ids" {
  description = "Private subnet IDs that can be used by internal resources. Required when create_ecs_services is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.create_ecs_services || length(var.private_subnet_ids) > 0
    error_message = "private_subnet_ids must contain at least one subnet id when create_ecs_services is true."
  }

  validation {
    condition     = alltrue([for id in var.private_subnet_ids : length(trimspace(id)) > 0])
    error_message = "private_subnet_ids must not contain empty strings."
  }
}

variable "public_subnet_ids" {
  description = "Public subnet IDs that can be used by public resources."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.public_subnet_ids : length(trimspace(id)) > 0])
    error_message = "public_subnet_ids must not contain empty strings."
  }
}

# Security Groups

variable "create_sg_rds_primary" {
  description = "Whether to create the default primary RDS security group (rds_primary)."
  type        = bool
  default     = true
}

variable "create_sg_rds_external_access" {
  description = "Whether to create a security group that allows external IP access to the RDS database on port 1521."
  type        = bool
  default     = false
}

variable "rds_external_access_cidrs" {
  description = "List of CIDR blocks allowed to access the RDS database on port 1521 via the rds_external_access security group. Each entry must be in CIDR notation (e.g. 192.168.0.1/32)."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.create_sg_rds_external_access || length(var.rds_external_access_cidrs) > 0
    error_message = "rds_external_access_cidrs must be non-empty when create_sg_rds_external_access is true."
  }
}

variable "security_groups" {
  description = "Additional security groups to create. This map is merged on top of the default rds_primary and ecs_services groups."
  type = map(object({
    name            = string
    description     = string
    vpc_id          = string
    use_name_prefix = optional(bool, false)
    ingress_with_cidr_blocks = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      description = optional(string)
      cidr_blocks = string
    })), [])
    egress_with_cidr_blocks = optional(list(object({
      from_port   = number
      to_port     = number
      protocol    = string
      description = optional(string)
      cidr_blocks = string
    })), [])
    tags = optional(map(string), {})
  }))
  default = {}
}

# RDS

variable "db_instance" {
  description = "Configuration object for the RDS instance (new schema)."
  type = list(object({
    # Engine
    engine         = optional(string, "oracle-se2")
    engine_version = optional(string, "19")
    license_model  = optional(string, "license-included")

    # Parameter / option groups
    parameter_group_name = string
    option_group_name    = string

    # Instance sizing / storage
    instance_class     = string
    allocated_storage  = number
    storage_type       = string
    iops               = optional(number)
    storage_throughput = optional(number)
    multi_az           = bool

    # Minor upgrades / certificates
    auto_minor_version_upgrade = optional(bool, true)
    ca_cert_identifier         = optional(string, "")
    kms_key_id                 = optional(string)

    # Credentials (ignored when restoring from snapshot)
    username = optional(string, "master")

    # Networking
    db_subnet_group_name   = string
    publicly_accessible    = optional(bool, false)
    vpc_security_group_ids = optional(list(string), [])

    # Backups / snapshots
    snapshot_identifier     = optional(string, "")
    backup_retention_period = optional(number, 0)
    copy_tags_to_snapshot   = optional(bool, false)

    # Lifecycle / protection
    deletion_protection = bool
    skip_final_snapshot = optional(bool, false)

    # Monitoring
    monitoring_interval = optional(number, 0)
    monitoring_role_arn = string

    # Performance Insights
    performance_insights_enabled = optional(bool, false)

    # IAM associations
    # map(feature_name => role_arn)
    db_instance_role_associations = optional(map(string), {})
  }))

  validation {
    condition     = length(var.db_instance) == 1
    error_message = "db_instance must contain exactly one object (list length must be 1)."
  }

  validation {
    condition     = length(trimspace(var.db_instance[0].db_subnet_group_name)) > 0
    error_message = "db_instance[0].db_subnet_group_name must be a non-empty string."
  }

  validation {
    condition     = length(trimspace(var.db_instance[0].engine)) > 0
    error_message = "db_instance[0].engine must be a non-empty string."
  }

  validation {
    condition     = var.db_instance[0].engine_version == null || length(trimspace(var.db_instance[0].engine_version)) > 0
    error_message = "db_instance[0].engine_version must be a non-empty string when set."
  }

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.db_instance[0].monitoring_interval)
    error_message = "db_instance[0].monitoring_interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }

  validation {
    condition     = length(trimspace(var.db_instance[0].monitoring_role_arn)) > 0
    error_message = "db_instance[0].monitoring_role_arn must be a non-empty string."
  }
}

variable "rds_schema" {
  description = "Schema name for the app RDS database."
  type        = string
  default     = "app"

  validation {
    condition     = length(trimspace(var.rds_schema)) > 0
    error_message = "rds_schema must be a non-empty string."
  }
}

# IAM

variable "iam_roles" {
  description = "Additional IAM roles to create. This map is merged on top of the default eks_service_account role."
  type = map(object({
    name                      = string
    use_name_prefix           = optional(bool, false)
    trust_policy_permissions  = any
    create_inline_policy      = optional(bool, false)
    inline_policy_permissions = optional(any, {})
    tags                      = optional(map(string), {})
  }))
  default = {}
}

variable "create_iam_role_eks_service_account" {
  description = "Whether to create the default EKS service account IAM role (eks_service_account)."
  type        = bool
  default     = false
}

variable "oidc_provider_arn" {
  description = "ARN OIDC provider EKS cluster."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_iam_role_eks_service_account || length(trimspace(var.oidc_provider_arn)) > 0
    error_message = "oidc_provider_arn must be a non-empty string when create_iam_role_eks_service_account is true."
  }
}

# Secrets Manager

variable "oracle_rotation_lambda_arn" {
  description = "Optional ARN of the Lambda function used for rotating Oracle RDS passwords. When unset, the module still creates the secrets but skips automatic rotation for the default RDS user secrets."
  type        = string
  default     = ""
}

variable "rds_users" {
  description = "Map of RDS users and their Secrets Manager rotation settings. Rotation is enabled by default for all users."
  type = map(object({
    rotation_enabled                     = optional(bool, true)
    rotation_schedule_expression_prod    = string
    rotation_schedule_expression_nonprod = string
  }))
  default = {
    app = {
      rotation_enabled                     = true
      rotation_schedule_expression_prod    = "cron(0 07 ? 1/3 1L *)"
      rotation_schedule_expression_nonprod = "cron(0 11 ? 1/3 2L *)"
    }
    master = {
      rotation_enabled                     = true
      rotation_schedule_expression_prod    = "cron(0 07 ? 1/3 1L *)"
      rotation_schedule_expression_nonprod = "cron(0 11 ? 1/3 2L *)"
    }
    readonly = {
      rotation_enabled                     = true
      rotation_schedule_expression_prod    = "cron(0 07 ? 1/3 1L *)"
      rotation_schedule_expression_nonprod = "cron(0 11 ? 1/3 2L *)"
    }
  }

  validation {
    condition     = alltrue([for u in keys(var.rds_users) : length(trimspace(u)) > 0])
    error_message = "rds_users must not contain empty usernames."
  }

  validation {
    condition     = contains(keys(var.rds_users), "master")
    error_message = "rds_users must include the 'master' user."
  }

  validation {
    condition     = alltrue([for _, cfg in var.rds_users : length(trimspace(cfg.rotation_schedule_expression_prod)) > 0 && length(trimspace(cfg.rotation_schedule_expression_nonprod)) > 0])
    error_message = "rds_users rotation schedule expressions must be non-empty strings."
  }
}

variable "secrets_manager_secrets" {
  description = "Additional Secrets Manager secrets to create. This map is merged on top of the default RDS user secrets."
  type = map(object({
    name                    = string
    description             = optional(string)
    secret_string           = string
    recovery_window_in_days = optional(number, 0)
    ignore_secret_changes   = optional(bool, true)
    kms_key_id              = optional(string)
    tags                    = optional(map(string), {})
    rotation = optional(object({
      enabled             = optional(bool, false)
      lambda_arn          = string
      schedule_expression = string
      duration            = optional(string, "1h")
      rotate_immediately  = optional(bool, false)
    }))
  }))
  default = {}
}

# Kubernetes

variable "create_kubernetes_resources" {
  description = "Whether to create Kubernetes resources (namespace, secrets, etc.)."
  type        = bool
  default     = false
}

variable "valkey_endpoint" {
  description = "Valkey endpoint URL for Backend to connect to Valkey service."
  type        = string

  validation {
    condition     = length(trimspace(var.valkey_endpoint)) > 0
    error_message = "valkey_endpoint must be a non-empty string."
  }
}

variable "valkey_security_group_id" {
  description = "Security group ID of the existing Valkey cluster used to allow ingress from ECS services."
  type        = string
  default     = null

  validation {
    condition     = !var.create_ecs_services || (var.valkey_security_group_id != null && length(trimspace(var.valkey_security_group_id)) > 0)
    error_message = "valkey_security_group_id must be provided when create_ecs_services is true."
  }
}

# Environment Schedule

variable "environment_schedule" {
  description = "Centralized schedule configuration for the environment. Each sub-block is independent: presence of the block enables that schedule, absence disables it."
  type = object({
    timezone = optional(string, "UTC")

    start_stop = optional(object({
      start_offset_minutes = optional(number, 15)
      start                = object({ schedule_expression = string })
      stop                 = object({ schedule_expression = string })
    }), null)

    rds_dump = optional(object({
      schedule_expression = string
    }), null)
  })
  default = {}
}

variable "lambda_rds_start_stop_instance_function_arn" {
  description = "The ARN of the Lambda function to start/stop RDS instance. Required when environment_schedule.start_stop is set."
  type        = string
  default     = ""

  validation {
    condition     = var.environment_schedule.start_stop == null || length(var.lambda_rds_start_stop_instance_function_arn) > 0
    error_message = "lambda_rds_start_stop_instance_function_arn must be set when environment_schedule.start_stop is configured."
  }
}

variable "eventbridge_schedulesets" {
  description = "Additional EventBridge schedule sets to create. This map is merged on top of the default rds_start_stop_instance set."
  type = map(object({
    create_bus           = optional(bool, false)
    role_name            = optional(string)
    attach_lambda_policy = optional(bool, false)
    lambda_target_arns   = optional(list(string), [])
    schedules = map(object({
      description         = optional(string)
      schedule_expression = string
      timezone            = optional(string)
      arn                 = optional(string)
      input               = optional(string)
    }))
    tags = optional(map(string), {})
  }))
  default = {}
}

# Lambdas

variable "create_lambda_rds_dump_step_function" {
  description = "Whether to create the RDS dump step-function trigger Lambda."
  type        = bool
  default     = false
}

variable "lambda_rds_dump_sql_updates" {
  description = "SQL statements passed to the RDS dump automation Lambda."
  type        = string
  default     = ""
}

variable "step_functions_rds_dump_state_machine_arn" {
  description = "Step Functions state machine ARN used by the RDS dump automation Lambda."
  type        = string
  default     = ""

  validation {
    condition     = !var.create_lambda_rds_dump_step_function || length(trimspace(var.step_functions_rds_dump_state_machine_arn)) > 0
    error_message = "When create_lambda_rds_dump_step_function is true, step_functions_rds_dump_state_machine_arn must be set."
  }
}

variable "lambda_rds_oracle_execute_sql_statements" {
  description = "Lambda function name or ARN used to execute SQL statements against the Oracle RDS instance."
  type        = string

  validation {
    condition     = !var.create_lambda_rds_dump_step_function || length(trimspace(var.lambda_rds_oracle_execute_sql_statements)) > 0
    error_message = "When create_lambda_rds_dump_step_function is true, lambda_rds_oracle_execute_sql_statements must be set."
  }
}

variable "lambda_rds_oracle_update_users_credentials" {
  description = "Lambda function name or ARN used to update Oracle RDS user credentials."
  type        = string

  validation {
    condition     = length(trimspace(var.lambda_rds_oracle_update_users_credentials)) > 0
    error_message = "lambda_rds_oracle_update_users_credentials must be a non-empty string."
  }
}

# SSM Parameter Store

variable "ssm_parameters" {
  description = "Additional SSM parameters to create. This map is merged on top of the default app_rds_config parameter."
  type = map(object({
    name            = string
    description     = optional(string)
    type            = optional(string, "String")
    value           = string
    overwrite       = optional(bool, true)
    tier            = optional(string)
    key_id          = optional(string)
    allowed_pattern = optional(string)
    data_type       = optional(string)
    tags            = optional(map(string), {})
  }))
  default = {}
}

# S3

variable "create_bucket_files" {
  description = "Whether to create the default 'files' bucket for the application."
  type        = bool
  default     = false # default must to be always false, because this resource is created only in the production environment
}

variable "create_bucket_temp" {
  description = "Whether to create the default 'temp' bucket for the application."
  type        = bool
  default     = false # default must to be always false, because this resource is created only in the production environment
}

variable "additional_s3_buckets" {
  description = "Additional buckets to create. Map of bucket_key -> bucket_name (merged on top of defaults)."
  type        = map(string)
  default     = {}
}

variable "s3_attach_policy" {
  description = "Whether to attach the default bucket policy (SSE enforcement + deny insecure transport)."
  type        = bool
  default     = true
}

variable "s3_bucket_policy_sse_algorithm" {
  description = "SSE algorithm required by the default S3 policy via s3:x-amz-server-side-encryption (e.g., AES256 or aws:kms)."
  type        = string
  default     = "AES256"
}

variable "s3_versioning_enabled" {
  description = "Whether to enable versioning on all buckets created by this stack."
  type        = bool
  default     = true
}

variable "s3_bucket_tags" {
  description = "Common tags applied to all buckets created by this stack."
  type        = map(string)
  default = {
    Backup = "yes"
  }
}

variable "s3_per_bucket_tags" {
  description = "Optional extra tags per bucket key (merged on top of s3_bucket_tags)."
  type        = map(map(string))
  default     = {}
}

# ECS

variable "create_ecs_services" {
  description = "Whether to create the ECS services defined in ecs-services.tf."
  type        = bool
  default     = false
}

variable "cluster_arn" {
  description = "Optional ECS cluster ARN used by ECS services. Must be set when create_ecs_services is true."
  type        = string
  default     = null

  validation {
    condition     = var.cluster_arn == null || length(trimspace(var.cluster_arn)) > 0
    error_message = "cluster_arn must be null or a non-empty string."
  }

  validation {
    condition     = !var.create_ecs_services || (var.cluster_arn != null && length(trimspace(var.cluster_arn)) > 0)
    error_message = "cluster_arn must be provided when create_ecs_services is true."
  }
}

variable "cloud_map_namespace_id" {
  description = "ID of the Cloud Map private DNS namespace used for ECS Service Discovery (Route 53 DNS-based)."
  type        = string
  default     = null
}

variable "alb_internal_security_group_id" {
  description = "Security group ID of the internal ALB. Used to allow health check traffic from the internal ALB to ECS services."
  type        = string
  default     = ""
}

variable "alb_public_security_group_id" {
  description = "Security group ID of the public ALB. Used to allow health check traffic from the public ALB to ECS services."
  type        = string
  default     = ""
}

variable "ecs_timezone" {
  description = "Default TIMEZONE value injected into ECS services."
  type        = string
  default     = "UTC"
}

variable "ecs_region" {
  description = "Default REGION value injected into ECS services."
  type        = string
  default     = "US"
}

variable "ecs_language" {
  description = "Default LANGUAGE value injected into ECS services."
  type        = string
  default     = "en"
}

variable "ecs_app_backend" {
  description = "Configuration overrides for the default backend ECS service settings."
  type = object({
    name                     = optional(string, "app-backend")
    repository               = optional(string, "123456789012.dkr.ecr.us-east-1.amazonaws.com/app/backend")
    image                    = optional(string, "1.0.0")
    cpu                      = optional(number, 1024)
    memory                   = optional(number, 3800)
    enable_autoscaling       = optional(bool, true)
    desired_count            = optional(number, 0)
    autoscaling_min_capacity = optional(number, 0)
    autoscaling_max_capacity = optional(number, 0)

    requires_compatibilities = optional(list(string), ["MANAGED_INSTANCES"])

    capacity_provider_strategy = optional(map(object({
      capacity_provider = string
      weight            = optional(number, 0)
      base              = optional(number, 0)
      })), {
      spot = {
        capacity_provider = "spot"
        weight            = 1
      }
    })

    autoscaling_policies = optional(any, {
      cpu = {
        policy_type = "TargetTrackingScaling"
        target_tracking_scaling_policy_configuration = {
          predefined_metric_specification = {
            predefined_metric_type = "ECSServiceAverageCPUUtilization"
          }
          target_value       = 70
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }
      }
    })

    deployment_circuit_breaker = optional(object({
      enable   = optional(bool, true)
      rollback = optional(bool, true)
      }), {
      enable   = true
      rollback = true
    })

    ordered_placement_strategy = optional(list(object({
      type  = string
      field = string
    })), [])

    availability_zone_rebalancing = optional(string, "DISABLED")
    wait_for_steady_state         = optional(bool, true)

    ssl_enabled = optional(bool, false)

    cloudwatch_log_group_retention_in_days = optional(number, 7)
  })
  default = {}
}

variable "ecs_app_frontend" {
  description = "Configuration overrides for the default frontend ECS service settings."
  type = object({
    name                     = optional(string, "app-frontend")
    repository               = optional(string, "123456789012.dkr.ecr.us-east-1.amazonaws.com/app/frontend")
    image                    = optional(string, "1.0.0")
    cpu                      = optional(number, 512)
    memory                   = optional(number, 256)
    enable_autoscaling       = optional(bool, true)
    desired_count            = optional(number, 0)
    autoscaling_min_capacity = optional(number, 0)
    autoscaling_max_capacity = optional(number, 0)

    requires_compatibilities = optional(list(string), ["MANAGED_INSTANCES"])

    capacity_provider_strategy = optional(map(object({
      capacity_provider = string
      weight            = optional(number, 0)
      base              = optional(number, 0)
      })), {
      spot = {
        capacity_provider = "spot"
        weight            = 1
      }
    })

    autoscaling_policies = optional(any, {
      cpu = {
        policy_type = "TargetTrackingScaling"
        target_tracking_scaling_policy_configuration = {
          predefined_metric_specification = {
            predefined_metric_type = "ECSServiceAverageCPUUtilization"
          }
          target_value       = 70
          scale_in_cooldown  = 300
          scale_out_cooldown = 60
        }
      }
    })

    deployment_circuit_breaker = optional(object({
      enable   = optional(bool, true)
      rollback = optional(bool, true)
      }), {
      enable   = true
      rollback = true
    })

    ordered_placement_strategy = optional(list(object({
      type  = string
      field = string
    })), [])

    availability_zone_rebalancing = optional(string, "DISABLED")
    wait_for_steady_state         = optional(bool, true)

    ssl_enabled = optional(bool, false)

    cloudwatch_log_group_retention_in_days = optional(number, 7)
  })
  default = {}
}

variable "route53_subdomain" {
  description = "The fully qualified subdomain from the route53-domain module (e.g., 'app.example.com'). Used to build ALB listener rule host headers as app-{resource_prefix}.{subdomain}."
  type        = string
  default     = ""
}

variable "internal_route53_zone" {
  description = "Internal Route53 zone for creating ALIAS records. The alb_dns_name/alb_zone_id define which ALB the record points to (typically the internal ALB, but can be any)."
  type = object({
    zone_id      = string
    alb_dns_name = string
    alb_zone_id  = string
  })
  default = null
}

variable "public_route53_zone" {
  description = "Public Route53 zone for creating ALIAS records. The alb_dns_name/alb_zone_id define which ALB the record points to (e.g., public ALB, or internal ALB for private-facing public DNS)."
  type = object({
    zone_id      = string
    alb_dns_name = string
    alb_zone_id  = string
  })
  default = null
}

variable "alb_public_https_listener_arn" {
  description = "ARN of the HTTPS listener on the public ALB. When set, creates public target groups and default listener rules for frontend and backend."
  type        = string
  default     = ""
}

variable "alb_internal_https_listener_arn" {
  description = "ARN of the HTTPS listener on the internal ALB. When set, creates internal target groups and default listener rules for frontend and backend."
  type        = string
  default     = ""
}

variable "alb_additional_listener_rules" {
  description = "Additional ALB listener rules beyond the module defaults. Keys are rule names, values define listener_arn, priority, target service, target_group_arn, and path conditions. Host is auto-generated as app-{environment}.{subdomain}."
  type = map(object({
    listener_arn     = string
    priority         = number
    service          = string
    target_group_arn = string
    paths            = optional(list(string), ["/*"])
  }))
  default = {}
}