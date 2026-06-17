# Transformation: aws-s3-checks-nis2 — NIS2 Directive (EU 2022/2555) S3
# plan-time assertions, mapped to Art.21(2) cybersecurity risk-management
# measures (Art.21(2)(h) cryptography/encryption, Art.21(2)(b) incident
# handling) and Art.23 reporting obligations.
#
# Framework-SPECIFIC. Structural hardening is in the generic `destroy` +
# `aws-s3-public-access` units; this adds only the NIS2 plan-time `check` block.
# Module binding: terraform-aws-modules/s3-bucket.

transform "new_block" nis2_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_nis2.tf"
  labels         = ["nis2_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[NIS2 Art.21(2)(h)] encryption at rest must be configured (cryptography and encryption)."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[NIS2 Art.21(2)(h)] non-TLS transport must be denied (cryptography — in transit)."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[NIS2 Art.21(2)(b) / Art.23] access logging must be configured for incident handling and reporting."
    }
  }
}
