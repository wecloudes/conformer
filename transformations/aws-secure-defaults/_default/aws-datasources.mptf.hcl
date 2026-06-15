# Declare the data sources the sanitization layer rewrites references to.
#
# patch-module.sh rewrites hardcoded AWS account IDs -> data.aws_caller_identity
# .current.account_id and hardcoded regions -> data.aws_region.current.name. If
# the module didn't already declare those data sources, the rewrite leaves a
# dangling reference. This injects them — but only when:
#   * the module is actually AWS (has aws_* resources), so we never add an
#     aws provider dependency to a non-AWS (e.g. Azure) module, and
#   * the data source isn't already declared (avoid a duplicate-address error).
#
# Unique data/locals names (aws_ds_*) so they don't collide with other packs.

data "resource" aws_ds_res {
}

data "data" aws_ds_existing {
}

locals {
  aws_ds_res_types = keys(try(data.resource.aws_ds_res.result, {}))
  aws_ds_is_aws    = length([for t in local.aws_ds_res_types : t if startswith(t, "aws_")]) > 0
  aws_ds_existing  = try(data.data.aws_ds_existing.result, {})

  aws_ds_inject_caller = (local.aws_ds_is_aws &&
    !contains(keys(try(local.aws_ds_existing.aws_caller_identity, {})), "current")) ? ["current"] : []
  aws_ds_inject_region = (local.aws_ds_is_aws &&
    !contains(keys(try(local.aws_ds_existing.aws_region, {})), "current")) ? ["current"] : []
}

transform "new_block" aws_ds_caller_identity {
  for_each       = toset(local.aws_ds_inject_caller)
  new_block_type = "data"
  filename       = "_conformer_data.tf"
  labels         = ["aws_caller_identity", each.value]
  body           = ""
}

transform "new_block" aws_ds_region {
  for_each       = toset(local.aws_ds_inject_region)
  new_block_type = "data"
  filename       = "_conformer_data.tf"
  labels         = ["aws_region", each.value]
  body           = ""
}
