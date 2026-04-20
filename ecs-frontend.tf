locals {
  app_frontend_port     = var.ecs_app_frontend.ssl_enabled ? 8443 : 8080
  app_frontend_protocol = var.ecs_app_frontend.ssl_enabled ? "HTTPS" : "HTTP"
}

locals {
  ecs_service_app_frontend = {
    name   = "${var.ecs_app_frontend.name}-${var.environment}"
    cpu    = var.ecs_app_frontend.cpu
    memory = var.ecs_app_frontend.memory

    desired_count            = var.ecs_app_frontend.desired_count
    enable_autoscaling       = var.ecs_app_frontend.enable_autoscaling
    autoscaling_min_capacity = var.ecs_app_frontend.autoscaling_min_capacity
    autoscaling_max_capacity = var.ecs_app_frontend.autoscaling_max_capacity

    autoscaling_policies = var.ecs_app_frontend.autoscaling_policies

    requires_compatibilities = var.ecs_app_frontend.requires_compatibilities

    capacity_provider_strategy = var.ecs_app_frontend.capacity_provider_strategy

    deployment_circuit_breaker = var.ecs_app_frontend.deployment_circuit_breaker

    ordered_placement_strategy = var.ecs_app_frontend.ordered_placement_strategy

    availability_zone_rebalancing = var.ecs_app_frontend.availability_zone_rebalancing
    wait_for_steady_state         = var.ecs_app_frontend.wait_for_steady_state

    autoscaling_scheduled_actions = local.start_stop_enabled ? {
      scale_up = {
        min_capacity = var.ecs_app_frontend.autoscaling_min_capacity
        max_capacity = var.ecs_app_frontend.autoscaling_max_capacity
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
      frontend = {
        name              = "${var.ecs_app_frontend.name}-${var.environment}"
        memory            = var.ecs_app_frontend.memory
        memoryReservation = var.ecs_app_frontend.memory
        essential         = true

        image = "${var.ecs_app_frontend.repository}:${var.ecs_app_frontend.image}"

        healthCheck = {
          command     = ["CMD-SHELL", var.ecs_app_frontend.ssl_enabled ? "curl -fk https://localhost:${local.app_frontend_port}/ || exit 1" : "curl -f http://localhost:${local.app_frontend_port}/ || exit 1"]
          interval    = 30
          timeout     = 15
          retries     = 10
          startPeriod = 30
        }

        portMappings = [
          {
            name          = "${var.ecs_app_frontend.name}-${var.environment}"
            containerPort = local.app_frontend_port
            hostPort      = local.app_frontend_port
            protocol      = "tcp"
            appProtocol   = "http"
          }
        ]

        environment = [
          { name = "CONTAINER_MODE", value = "local" },
          { name = "SSL_ENABLED", value = var.ecs_app_frontend.ssl_enabled ? "true" : "false" },
        ]

        # Example image used requires access to write to root filesystem
        readonlyRootFilesystem = false

        enable_cloudwatch_logging              = true
        create_cloudwatch_log_group            = true
        cloudwatch_log_group_name              = "${local.ecs_log_group_prefix}/${var.ecs_app_frontend.name}-${var.environment}"
        cloudwatch_log_group_retention_in_days = var.ecs_app_frontend.cloudwatch_log_group_retention_in_days

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
          target_group_arn = aws_lb_target_group.app_frontend_internal[0].arn
          container_name   = "${var.ecs_app_frontend.name}-${var.environment}"
          container_port   = local.app_frontend_port
        }
      } : {},
      var.alb_public_https_listener_arn != "" ? {
        public = {
          target_group_arn = aws_lb_target_group.app_frontend_public[0].arn
          container_name   = "${var.ecs_app_frontend.name}-${var.environment}"
          container_port   = local.app_frontend_port
        }
      } : {}
    )
    security_group_ingress_rules = merge(
      var.alb_internal_security_group_id != "" ? {
        alb_internal = {
          ip_protocol                  = "tcp"
          from_port                    = local.app_frontend_port
          to_port                      = local.app_frontend_port
          referenced_security_group_id = var.alb_internal_security_group_id
          description                  = "Allow traffic from internal ALB"
        }
      } : {},
      var.alb_public_security_group_id != "" ? {
        alb_public = {
          ip_protocol                  = "tcp"
          from_port                    = local.app_frontend_port
          to_port                      = local.app_frontend_port
          referenced_security_group_id = var.alb_public_security_group_id
          description                  = "Allow traffic from public ALB"
        }
      } : {}
    )
  }
}

resource "aws_lb_target_group" "app_frontend_internal" {
  count = var.create_ecs_services && var.alb_internal_https_listener_arn != "" ? 1 : 0

  name        = "${var.ecs_app_frontend.name}-${var.environment}-internal"
  port        = local.app_frontend_port
  protocol    = local.app_frontend_protocol
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = local.app_frontend_protocol
    matcher             = "200"
    interval            = 60
    timeout             = 30
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  vpc_id = var.vpc_id
}

resource "aws_lb_target_group" "app_frontend_public" {
  count = var.create_ecs_services && var.alb_public_https_listener_arn != "" ? 1 : 0

  name        = "${var.ecs_app_frontend.name}-${var.environment}-public"
  port        = local.app_frontend_port
  protocol    = local.app_frontend_protocol
  target_type = "ip"

  health_check {
    path                = "/"
    protocol            = local.app_frontend_protocol
    matcher             = "200"
    interval            = 60
    timeout             = 30
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }

  vpc_id = var.vpc_id
}

locals {
  ecs_alb_listener_app_frontend = merge(
    var.alb_internal_https_listener_arn != "" ? {
      frontend-internal-https = {
        listener_arn     = var.alb_internal_https_listener_arn
        priority         = 100
        paths            = ["/*"]
        target_group_arn = aws_lb_target_group.app_frontend_internal[0].arn
      }
    } : {},
    var.alb_public_https_listener_arn != "" ? {
      frontend-public-https = {
        listener_arn     = var.alb_public_https_listener_arn
        priority         = 100
        paths            = ["/*"]
        target_group_arn = aws_lb_target_group.app_frontend_public[0].arn
      }
    } : {}
  )
}

resource "aws_lb_listener_rule" "app_frontend" {
  for_each = {
    for k, v in merge(
      local.ecs_alb_listener_app_frontend,
      { for k, v in var.alb_additional_listener_rules : k => v if v.service == var.ecs_app_frontend.name }
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
    Name = var.ecs_app_frontend.name
  }
}

# Route53 ALIAS records

resource "aws_route53_record" "app_frontend_internal" {
  count = var.internal_route53_zone != null && var.create_ecs_services ? 1 : 0

  zone_id = var.internal_route53_zone.zone_id
  name    = "app-${var.environment}"
  type    = "A"

  alias {
    name                   = var.internal_route53_zone.alb_dns_name
    zone_id                = var.internal_route53_zone.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "app_frontend_public" {
  count = var.public_route53_zone != null && var.create_ecs_services ? 1 : 0

  zone_id = var.public_route53_zone.zone_id
  name    = "app-${var.environment}"
  type    = "A"

  alias {
    name                   = var.public_route53_zone.alb_dns_name
    zone_id                = var.public_route53_zone.alb_zone_id
    evaluate_target_health = true
  }
}
