# CIS AWS Foundations Benchmark v6.0.0 — S3 Bucket structural transforms
#
# These are mapotf (github.com/Azure/mapotf) transform rules. Unlike the
# advisory toggles in patch.hcl (source-time layer), these mutate the ACTUAL
# upstream resources: they inject lifecycle protection and override insecure
# attribute values so compliance cannot be turned off by the caller.
#
# Same file drives both deployment models:
#   - Model A (registry): run by the Tekton patch task against the cloned module.
#   - Model B (direct):   run by the consumer via `mapotf transform`.

variable "prevent_destroy" {
  type    = bool
  default = true
}

# --- CIS 2.1.x / 3.3 : query the resources we need to harden ------------------

data "resource" bucket {
  resource_type = "aws_s3_bucket"
}

data "resource" pab {
  resource_type = "aws_s3_bucket_public_access_block"
}

# --- CIS data protection : prevent accidental bucket destruction --------------
# Slide 27 (lifecycle injection), done structurally instead of `hcledit append`.
transform "update_in_place" cis_prevent_destroy {
  for_each             = try(data.resource.bucket.result.aws_s3_bucket, {})
  target_block_address = each.value.mptf.block_address

  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
    }
  }
}

# --- CIS 3.3 : block ALL public access, overriding any caller value -----------
# Attribute restriction (slide 29) enforced at source: the four flags are set
# to true regardless of what the consumer passed.
transform "update_in_place" cis_block_public_access {
  for_each             = try(data.resource.pab.result.aws_s3_bucket_public_access_block, {})
  target_block_address = each.value.mptf.block_address

  asraw {
    block_public_acls       = true
    block_public_policy      = true
    ignore_public_acls       = true
    restrict_public_buckets  = true
  }
}

# --- CIS 2.1.1 / 2.1.2 / 2.1.4 : plan-time assertions on caller config --------
# A `check` block surfaces non-compliant configuration as a plan warning and,
# paired with the jq gate (slide 29 layer 2), fails CI.
transform "new_block" cis_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_cis.tf"
  labels         = ["cis_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[CIS 2.1.1] server_side_encryption_configuration must be set."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[CIS 2.1.2] attach_deny_insecure_transport_policy must be true (deny non-TLS)."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[CIS 2.1.4] access logging must be configured."
    }
  }
}
