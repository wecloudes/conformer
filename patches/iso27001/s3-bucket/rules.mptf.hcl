# ISO/IEC 27001:2022 — S3 Bucket structural transforms (mapotf)
#
# Stricter than CIS: ISO A.8.24 requires KMS (not AES256) and A.8.10 requires
# lifecycle rules for data retention. Same dual-use as the CIS rules file.

variable "prevent_destroy" {
  type    = bool
  default = true
}

data "resource" bucket {
  resource_type = "aws_s3_bucket"
}

data "resource" pab {
  resource_type = "aws_s3_bucket_public_access_block"
}

# A.8.10 information deletion — protect data, prevent destroy (slide 27).
transform "update_in_place" iso_prevent_destroy {
  for_each             = try(data.resource.bucket.result.aws_s3_bucket, {})
  target_block_address = each.value.mptf.block_address

  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
    }
  }
}

# A.8.3 information access restriction — lock public access (slide 29).
transform "update_in_place" iso_block_public_access {
  for_each             = try(data.resource.pab.result.aws_s3_bucket_public_access_block, {})
  target_block_address = each.value.mptf.block_address

  asraw {
    block_public_acls       = true
    block_public_policy      = true
    ignore_public_acls       = true
    restrict_public_buckets  = true
  }
}

# A.8.24 / A.8.15 / A.8.25 plan-time assertions.
transform "new_block" iso_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_iso27001.tf"
  labels         = ["iso27001_s3_controls"]
  asraw {
    assert {
      condition     = anytrue([for r in try(flatten([var.server_side_encryption_configuration["rule"]]), []) : try(r.apply_server_side_encryption_by_default[0].sse_algorithm, r.apply_server_side_encryption_by_default.sse_algorithm, "") == "aws:kms"])
      error_message = "[ISO27001 A.8.24] encryption must use aws:kms, not AES256."
    }
    assert {
      condition     = length(keys(var.versioning)) > 0
      error_message = "[ISO27001 A.8.25] versioning must be enabled for data integrity."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[ISO27001 A.8.15] access logging must be enabled."
    }
  }
}
