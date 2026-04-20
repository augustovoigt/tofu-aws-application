locals {
  # ECS autoscaling scheduled actions derived from environment_schedule.start_stop
  # The start schedule is offset by start_offset_minutes to allow RDS to become available first
  ecs_scheduled_actions_start_expression = local.start_stop_enabled ? (
    # Parse cron: "cron(M H ? * DOW *)" → offset minutes
    # regex captures: minute, hour, rest
    format("cron(%d %s)",
      (tonumber(regex("^cron\\((\\d+)\\s", var.environment_schedule.start_stop.start.schedule_expression)[0]) + var.environment_schedule.start_stop.start_offset_minutes) % 60,
      # If minutes overflow past 60, increment hour
      (tonumber(regex("^cron\\((\\d+)\\s", var.environment_schedule.start_stop.start.schedule_expression)[0]) + var.environment_schedule.start_stop.start_offset_minutes) >= 60
      ? format("%d %s",
        tonumber(regex("^cron\\(\\d+\\s(\\d+)\\s", var.environment_schedule.start_stop.start.schedule_expression)[0]) + 1,
        regex("^cron\\(\\d+\\s\\d+\\s(.+)\\)$", var.environment_schedule.start_stop.start.schedule_expression)[0]
      )
      : format("%s %s",
        regex("^cron\\(\\d+\\s(\\d+)\\s", var.environment_schedule.start_stop.start.schedule_expression)[0],
        regex("^cron\\(\\d+\\s\\d+\\s(.+)\\)$", var.environment_schedule.start_stop.start.schedule_expression)[0]
      )
    )
  ) : ""

  ecs_service_defaults = {
    cluster_arn        = var.cluster_arn
    subnet_ids         = var.private_subnet_ids
    security_group_ids = var.create_ecs_services ? [module.security_groups["ecs_services"].security_group_id] : []

    security_group_ingress_rules = {}

    security_group_egress_rules = {
      all = {
        ip_protocol = "-1"
        cidr_ipv4   = "0.0.0.0/0"
      }
    }

    # tags = {
    #   Environment = "dev"
    #   Terraform   = "true"
    # }
  }

  ecs_services = {
    (local.ecs_service_app_backend.name)  = local.ecs_service_app_backend
    (local.ecs_service_app_frontend.name) = local.ecs_service_app_frontend
  }
}

module "ecs_service" {
  for_each = {
    for service_name, service in local.ecs_services : service_name => service
    if var.create_ecs_services
  }

  source = "terraform-aws-modules/ecs/aws//modules/service"

  name        = each.value.name
  cluster_arn = local.ecs_service_defaults.cluster_arn

  cpu    = each.value.cpu
  memory = each.value.memory

  enable_execute_command = true

  requires_compatibilities   = try(each.value.requires_compatibilities, null)
  capacity_provider_strategy = try(each.value.capacity_provider_strategy, null)
  deployment_circuit_breaker = try(each.value.deployment_circuit_breaker, null)
  ordered_placement_strategy = try(each.value.ordered_placement_strategy, null)

  desired_count                 = try(each.value.desired_count, null)
  enable_autoscaling            = try(each.value.enable_autoscaling, null)
  availability_zone_rebalancing = try(each.value.availability_zone_rebalancing, null)
  wait_for_steady_state         = try(each.value.wait_for_steady_state, null)

  autoscaling_scheduled_actions = try(each.value.autoscaling_scheduled_actions, null)
  autoscaling_min_capacity      = try(each.value.autoscaling_min_capacity, null)
  autoscaling_max_capacity      = try(each.value.autoscaling_max_capacity, null)
  autoscaling_policies          = try(each.value.autoscaling_policies, null)

  force_delete = try(each.value.force_delete, null)

  security_group_ids = try(each.value.security_group_ids, local.ecs_service_defaults.security_group_ids)

  volume_configuration = try(each.value.volume_configuration, null)
  volume               = try(each.value.volume, null)

  container_definitions = each.value.container_definitions

  task_exec_iam_statements = try(each.value.task_exec_iam_statements, null)
  tasks_iam_role_statements = concat(
    [
      {
        sid = "AllowECSExec"
        actions = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel",
        ]
        resources = ["*"]
      }
    ],
    try(each.value.tasks_iam_role_statements, [])
  )

  service_registries = try(each.value.service_registries, null)
  load_balancer      = try(each.value.load_balancer, {})

  subnet_ids = local.ecs_service_defaults.subnet_ids

  security_group_ingress_rules = merge(
    local.ecs_service_defaults.security_group_ingress_rules,
    try(each.value.security_group_ingress_rules, {})
  )
  security_group_egress_rules = local.ecs_service_defaults.security_group_egress_rules

  # tags = merge(
  #   local.ecs_service_defaults.tags,
  #   try(each.value.tags, {})
  # )

  tags = {
    Name = each.value.name
  }
}