# Model B unit — sources the REAL upstream module (no fork). The before_hook in
# root.hcl runs mapotf against the downloaded copy before terraform plan/apply.
#
# merge_strategy = "deep" so this unit's `source` merges with the hooks defined
# in root.hcl's `terraform` block.

include "root" {
  path           = find_in_parent_folders("root.hcl")
  merge_strategy = "deep"
}

terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git//.?ref=v5.11.0"
}

inputs = {
  bucket = "my-bucket"

  # Leave these out / non-compliant to watch the plan-gate fire; add them to go
  # green. mapotf already forces public-access shut and injects prevent_destroy
  # regardless of what is set here.
  attach_deny_insecure_transport_policy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "aws:kms"
      }
    }
  }

  versioning = { enabled = true }
}
