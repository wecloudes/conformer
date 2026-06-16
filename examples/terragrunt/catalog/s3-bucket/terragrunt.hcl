# Catalog unit — CIS-hardened terraform-aws-modules/s3-bucket from the registry.
# `terraform` runs unmodified; enforcement was baked in at build time and is
# gated by the registry's token/entitlement check. The host comes from root.hcl.

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

terraform {
  source = "tfr://${include.root.locals.framework_host}/terraform-aws-modules/s3-bucket/aws?version=5.11.0"
}

inputs = {
  bucket = "my-compliant-bucket"

  # The caller still supplies the config the controls require; the registry's
  # plan-time `check` blocks (and scripts/plan-gate.sh) assert these are present.
  attach_deny_insecure_transport_policy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
    }
  }

  versioning = { enabled = true }

  logging = {
    target_bucket = "my-log-bucket"
    target_prefix = "s3/my-compliant-bucket/"
  }
}
