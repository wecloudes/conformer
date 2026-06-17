# Transformation: aws-s3-checks-nist — NIST SP 800-53 Rev 5 S3 plan-time
# assertions, mapped to the relevant control families (SC-28 / SC-8 / SC-13 /
# AU-2 / AU-12).
#
# Framework-SPECIFIC. Structural hardening is in the generic `destroy` +
# `aws-s3-public-access` units; this adds only the NIST plan-time `check` block.
# Module binding: terraform-aws-modules/s3-bucket.

transform "new_block" nist_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_nist_800_53.tf"
  labels         = ["nist_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[NIST SC-28] encryption at rest must be configured (Protection of Information at Rest)."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[NIST SC-8] non-TLS transport must be denied (Transmission Confidentiality and Integrity / SC-13 Cryptographic Protection)."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[NIST AU-2] access logging must be enabled (Event Logging / AU-12 Audit Record Generation)."
    }
  }
}
