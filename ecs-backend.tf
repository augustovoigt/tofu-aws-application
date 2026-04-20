locals {
  app_backend_port     = var.ecs_app_backend.ssl_enabled ? 8443 : 8080
  app_backend_protocol = var.ecs_app_backend.ssl_enabled ? "HTTPS" : "HTTP"
}

locals {
  ecs_service_app_backend = {
    name   = "${var.ecs_app_backend.name}-${var.environment}"
    cpu    = var.ecs_app_backend.cpu
    memory = var.ecs_app_backend.memory

    desired_count            = var.ecs_app_backend.desired_count
    enable_autoscaling       = var.ecs_app_backend.enable_autoscaling
    autoscaling_min_capacity = var.ecs_app_backend.autoscaling_min_capacity
    autoscaling_max_capacity = var.ecs_app_backend.autoscaling_max_capacity

    autoscaling_policies = var.ecs_app_backend.autoscaling_policies

    requires_compatibilities = var.ecs_app_backend.requires_compatibilities

    capacity_provider_strategy = var.ecs_app_backend.capacity_provider_strategy

    deployment_circuit_breaker = var.ecs_app_backend.deployment_circuit_breaker

    ordered_placement_strategy = var.ecs_app_backend.ordered_placement_strategy

    availability_zone_rebalancing = var.ecs_app_backend.availability_zone_rebalancing
    wait_for_steady_state         = var.ecs_app_backend.wait_for_steady_state

    autoscaling_scheduled_actions = local.start_stop_enabled ? {
      scale_up = {
        min_capacity = var.ecs_app_backend.autoscaling_min_capacity
        max_capacity = var.ecs_app_backend.autoscaling_max_capacity
        schedule     = local.ecs_scheduled_actions_start_expression
        timezone     = var.environment_schedule.timezone
      }
      scale_down = {
        min_capacity = 0
        max_capacity = 0
        schedule     = var.environment_schedule.start_stop.stop.schedule_expression
        timezone     = var.environment_schedule.timezone
      }
    } : null

    container_definitions = {
      backend = {
        name              = "${var.ecs_app_backend.name}-${var.environment}"
        memory            = var.ecs_app_backend.memory
        memoryReservation = var.ecs_app_backend.memory
        essential         = true

        image = "${var.ecs_app_backend.repository}:${var.ecs_app_backend.image}"

        healthCheck = {
          command     = ["CMD-SHELL", var.ecs_app_backend.ssl_enabled ? "curl -fk https://localhost:${local.app_backend_port}/api/metrics || exit 1" : "curl -f http://localhost:${local.app_backend_port}/api/metrics || exit 1"]
          interval    = 30
          timeout     = 15
          retries     = 10
          startPeriod = 120
        }

        portMappings = [
          {
            name          = "${var.ecs_app_backend.name}-${var.environment}"
            containerPort = local.app_backend_port
            hostPort      = local.app_backend_port
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]

        environment = [
          { name = "CONTAINER_MODE", value = "local" },
          { name = "JAVA_HOME", value = "/usr" },
          { name = "LANG", value = "en_US.UTF-8" },
          { name = "LC_ALL", value = "en_US.UTF-8" },
          { name = "HOSTNAME", value = "${var.ecs_app_backend.name}-${var.environment}" },
          { name = "SSL_ENABLED", value = var.ecs_app_backend.ssl_enabled ? "true" : "false" },
          { name = "TZ", value = "${var.ecs_timezone}" },
          { name = "XMX", value = "2048m" },
        ]

        secrets = [
          {
            name      = "DB_URL"
            valueFrom = "${module.secrets["rds_app_user_app"].secret_arn}:DB_URL::"
          },
          {
            name      = "DB_USER"
            valueFrom = "${module.secrets["rds_app_user_app"].secret_arn}:username::"
          },
          {
            name      = "DB_PASS"
            valueFrom = "${module.secrets["rds_app_user_app"].secret_arn}:password::"
          },
        ]

        # Example image used requires access to write to root filesystem
        readonlyRootFilesystem = false

        enable_cloudwatch_logging              = true
        create_cloudwatch_log_group            = true
        cloudwatch_log_group_name              = "${local.ecs_log_group_prefix}/${var.ecs_app_backend.name}-${var.environment}"
        cloudwatch_log_group_retention_in_days = var.ecs_app_backend.cloudwatch_log_group_retention_in_days

        logConfiguration = {
          logDriver = "awslogs"
        }

        # tasks_iam_role_policies = {
        #   ReadOnlyAccess = "arn:aws:iam::aws:policy/ReadOnlyAccess"
        # }

        # dependsOn = [{
        #   containerName = "example"
        #   condition     = "START"
        # }]

        restartPolicy = {
          enabled              = true
          ignoredExitCodes     = [1]
          restartAttemptPeriod = 60
        }
      }
    }

    load_balancer = merge(
      var.alb_internal_https_listener_arn != "" ? {
        internal = {
          target_group_arn = aws_lb_target_group.app_backend_internal[0].arn
          container_name   = "${var.ecs_app_backend.name}-${var.environment}"
          container_port   = local.app_backend_port
        }
      } : {},
      var.alb_public_https_listener_arn != "" ? {
        public = {
          target_group_arn = aws_lb_target_group.app_backend_public[0].arn
          container_name   = "${var.ecs_app_backend.name}-${var.environment}"
          container_port   = local.app_backend_port
        }
      } : {}
    )

    task_exec_iam_statements = [
      {
        actions = ["secretsmanager:GetSecretValue"]
        resources = [
          module.secrets["rds_app_user_app"].secret_arn,
        ]
      },
      {
        actions = [
          "ecs:Poll",
          "ecs:DiscoverPollEndpoint",
          "ecs:StartTelemetrySession",
          "ecs:UpdateTaskSet",
          "ecs:DescribeTaskSets"
        ]
        resources = ["*"]
      }
    ]

    tasks_iam_role_statements = [
      {
        sid       = "AllowListAllBuckets"
        actions   = ["s3:GetBucketLocation", "s3:ListAllMyBuckets", "s3:ListBucket"]
        resources = ["*"]
      },
      {
        sid     = "AllowActionsOnSpecificBuckets"
        actions = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
        resources = [
          "arn:aws:s3:::${local.s3_default_buckets.files.name}",
          "arn:aws:s3:::${local.s3_default_buckets.files.name}/*",
          "arn:aws:s3:::${local.s3_default_buckets.temp.name}",
          "arn:aws:s3:::${local.s3_default_buckets.temp.name}/*",
        ]
      }
    ]

    security_group_ingress_rules = merge(
      var.alb_internal_security_group_id != "" ? {
        alb_internal = {
          ip_protocol                  = "tcp"
          from_port                    = local.app_backend_port
          to_port                      = local.app_backend_port
          referenced_security_group_id = var.alb_internal_security_group_id
          description                  = "Allow traffic from internal ALB"
        }
      } : {},
      var.alb_public_security_group_id != "" ? {
        alb_public = {
          ip_protocol                  = "tcp"
          from_port                    = local.app_backend_port
          to_port                      = local.app_backend_port
          referenced_security_group_id = var.alb_public_security_group_id
          description                  = "Allow traffic from public ALB"
        }
      } : {}
    )
  }
}

resource "aws_lb_target_group" "app_backend_internal" {
  count = var.create_ecs_services && var.alb_internal_https_listener_arn != "" ? 1 : 0

  name        = "${var.ecs_app_backend.name}-${var.environment}-internal"
  port        = local.app_backend_port
  protocol    = local.app_backend_protocol
  target_type = "ip"

  health_check {
    path                = "/api/metrics"
    protocol            = local.app_backend_protocol
    matcher             = "200"
    interval            = 60
    timeout             = 30
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  vpc_id = var.vpc_id
}

resource "aws_lb_target_group" "app_backend_public" {
  count = var.create_ecs_services && var.alb_public_https_listener_arn != "" ? 1 : 0

  name        = "${var.ecs_app_backend.name}-${var.environment}-public"
  port        = local.app_backend_port
  protocol    = local.app_backend_protocol
  target_type = "ip"

  health_check {
    path                = "/api/metrics"
    protocol            = local.app_backend_protocol
    matcher             = "200"
    interval            = 60
    timeout             = 30
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  vpc_id = var.vpc_id
}

locals {
  ecs_alb_listener_app_backend = merge(
    var.alb_internal_https_listener_arn != "" ? {
      backend-internal-https = {
        listener_arn     = var.alb_internal_https_listener_arn
        priority         = 50
        paths            = ["/api/*"]
        target_group_arn = aws_lb_target_group.app_backend_internal[0].arn
      }
    } : {},
    var.alb_public_https_listener_arn != "" ? {
      backend-public-https = {
        listener_arn     = var.alb_public_https_listener_arn
        priority         = 50
        paths            = ["/api/*"]
        target_group_arn = aws_lb_target_group.app_backend_public[0].arn
      }
    } : {}
  )
}

resource "aws_lb_listener_rule" "app_backend" {
  for_each = {
    for k, v in merge(
      local.ecs_alb_listener_app_backend,
      { for k, v in var.alb_additional_listener_rules : k => v if v.service == var.ecs_app_backend.name }
    ) : k => v
    if var.create_ecs_services
  }

  listener_arn = each.value.listener_arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = each.value.target_group_arn
  }

  condition {
    host_header {
      values = ["app-${var.environment}.${strcontains(each.key, "internal") ? "internal." : ""}${var.route53_subdomain}"]
    }
  }

  condition {
    path_pattern {
      values = each.value.paths
    }
  }

  tags = {
    Name = var.ecs_app_backend.name
  }
}