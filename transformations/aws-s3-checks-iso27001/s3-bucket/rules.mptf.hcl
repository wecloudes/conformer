# Transformation: aws-s3-checks-iso27001 — ISO/IEC 27001:2022 S3 plan-time
# assertions. Stricter than CIS: A.8.24 requires KMS (not AES256).
#
# Framework-SPECIFIC. Structural hardening is in the generic `destroy` +
# `aws-s3-public-access` units; this adds only the ISO plan-time `check` block.
# Module binding: terraform-aws-modules/s3-bucket.

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
