locals {
  s3_default_bucket_policy = {
    version                = "2012-10-17"
    deny_s3_actions        = ["s3:*"]
    deny_all_principal     = "*"
    secure_transport_key   = "aws:SecureTransport"
    sse_header_key         = "s3:x-amz-server-side-encryption"
    insecure_transport_val = "false"
  }

  s3_default_buckets = {
    files = {
      create = var.create_bucket_files
      name   = "${var.resource_prefix}-files-${var.aws_account_id}-${var.aws_region}"
    }
    temp = {
      create = var.create_bucket_temp
      name   = "${var.resource_prefix}-temp-${var.aws_account_id}-${var.aws_region}"
    }
  }

  s3_buckets = merge(
    local.s3_default_buckets,
    {
      for bucket_key, bucket_name in var.additional_s3_buckets :
      bucket_key => {
        create = true
        name   = bucket_name
      }
    }
  )

  # Always expose bucket names for consumers (e.g., lambdas-invoke) even when
  # create_bucket_* is false. Bucket creation itself is controlled separately.
  app_s3_buckets = { for bucket_key, cfg in local.s3_buckets : bucket_key => cfg.name }

  app_s3_buckets_to_create = { for bucket_key, cfg in local.s3_buckets : bucket_key => cfg.name if cfg.create }

  s3_bucket_arns        = { for bucket_key, bucket_name in local.app_s3_buckets_to_create : bucket_key => "arn:aws:s3:::${bucket_name}" }
  s3_bucket_object_arns = { for bucket_key, bucket_name in local.app_s3_buckets_to_create : bucket_key => "arn:aws:s3:::${bucket_name}/*" }

  s3_default_bucket_policy_by_bucket = {
    for bucket_key, bucket_name in local.app_s3_buckets_to_create :
    bucket_key => jsonencode({
      Version = local.s3_default_bucket_policy.version
      Statement = [
        {
          Effect    = "Deny"
          Principal = local.s3_default_bucket_policy.deny_all_principal
          Action    = local.s3_default_bucket_policy.deny_s3_actions
          Resource  = [local.s3_bucket_object_arns[bucket_key]]
          Condition = {
            StringNotEqualsIfExists = {
              (local.s3_default_bucket_policy.sse_header_key) = var.s3_bucket_policy_sse_algorithm
            }
            Null = {
              (local.s3_default_bucket_policy.sse_header_key) = local.s3_default_bucket_policy.insecure_transport_val
            }
          }
        },
        {
          Sid       = "DenyInsecureRequests"
          Effect    = "Deny"
          Principal = local.s3_default_bucket_policy.deny_all_principal
          Action    = local.s3_default_bucket_policy.deny_s3_actions
          Resource = [
            local.s3_bucket_object_arns[bucket_key],
            local.s3_bucket_arns[bucket_key]
          ]
          Condition = {
            Bool = {
              (local.s3_default_bucket_policy.secure_transport_key) = local.s3_default_bucket_policy.insecure_transport_val
            }
          }
        }
      ]
    })
  }
}

module "s3_buckets" {
  source   = "terraform-aws-modules/s3-bucket/aws"
  version  = "5.10.0"
  for_each = local.app_s3_buckets_to_create

  bucket        = each.value
  attach_policy = var.s3_attach_policy

  policy = var.s3_attach_policy ? local.s3_default_bucket_policy_by_bucket[each.key] : null

  versioning = {
    enabled = var.s3_versioning_enabled
  }

  tags = merge(var.s3_bucket_tags, lookup(var.s3_per_bucket_tags, each.key, {}))
}