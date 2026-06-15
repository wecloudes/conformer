# Transformation: aws-s3-checks-cis — CIS v6.0.0 S3 plan-time assertions.
#
# Framework-SPECIFIC (the control thresholds differ per framework), so this unit
# is named per framework. Structural hardening (prevent_destroy, block public
# access) lives in the generic `destroy` + `aws-s3-public-access` units; this one
# only adds the CIS plan-time `check` block that the jq plan-gate turns into a
# CI failure. Module binding: terraform-aws-modules/s3-bucket.

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
