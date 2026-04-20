module "app_namespace" {
  source = "git::https://github.com/augustovoigt/tofu-aws-modules.git//modules/kubernetes/namespace/?ref=main"

  count = var.create_kubernetes_resources ? 1 : 0

  resource_prefix = var.resource_prefix
  app_name        = "app"
  environment     = var.environment
}
