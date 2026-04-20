locals {
  s3_access_resources = distinct(concat(
    [for _, cfg in local.s3_buckets : "arn:aws:s3:::${cfg.name}"],
    [for _, cfg in local.s3_buckets : "arn:aws:s3:::${cfg.name}/*"]
  ))

  iam_roles_default = {
    eks_service_account = {
      create = var.create_iam_role_eks_service_account
      name   = "${local.naming_prefix}-role-eks-sa-${var.aws_region}"

      trust_policy_permissions = var.oidc_provider_arn != null && var.oidc_provider_arn != "" ? {
        assumerolewithwebidentity = {
          sid     = "AssumeRoleWithWebIdentity"
          effect  = "Allow"
          actions = ["sts:AssumeRoleWithWebIdentity", "sts:TagSession"]
          principals = [{
            type        = "Federated"
            identifiers = [var.oidc_provider_arn]
          }]
        }
      } : {}

      create_inline_policy = true
      inline_policy_permissions = {
        KMSAccess = {
          sid       = "KMSAccess"
          effect    = "Allow"
          actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
          resources = ["*"]
          condition = [{
            test     = "StringEquals"
            variable = "kms:CallerAccount"
            values   = [var.aws_account_id]
          }]
        }
        SecretsManagerAccess = {
          sid     = "SecretsManagerAccess"
          effect  = "Allow"
          actions = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
          resources = distinct(compact(
            [for _, secret in module.secrets : secret.secret_arn]
          ))
        }
        S3Access = {
          sid    = "S3Access"
          effect = "Allow"
          actions = [
            "s3:DeleteObject",
            "s3:GetObject",
            "s3:PutObject",
            "s3:GetBucketLocation",
            "s3:ListBucket",
          ]
          resources = local.s3_access_resources
        }
        S3ListAllMyBuckets = {
          sid       = "S3ListAllMyBuckets"
          effect    = "Allow"
          actions   = ["s3:ListAllMyBuckets"]
          resources = ["*"]
        }
      }
      policies = {}
    }
  }

  iam_roles = merge(local.iam_roles_default, var.iam_roles)
}

module "iam_roles" {
  source   = "terraform-aws-modules/iam/aws//modules/iam-role"
  version  = "6.4.0"
  for_each = { for k, v in local.iam_roles : k => v if try(v.create, true) }

  name                      = each.value.name
  use_name_prefix           = false
  trust_policy_permissions  = each.value.trust_policy_permissions
  create_inline_policy      = each.value.create_inline_policy
  inline_policy_permissions = each.value.inline_policy_permissions
  policies                  = each.value.policies
}