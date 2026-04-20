resource "kubernetes_config_map_v1" "app_config" {
  count = var.create_kubernetes_resources ? 1 : 0

  metadata {
    name      = "${var.resource_prefix}-config-${var.environment}"
    namespace = try(module.app_namespace[0].name, "")
  }

  data = {
    ACCOUNTID      = var.aws_account_id
    REGION         = var.aws_region
    REDIS_ENDPOINT = "rediss://${var.valkey_endpoint}:6379"
  }

  depends_on = [module.app_namespace]
}
