# Transformation: aws-s3-checks-gdpr — GDPR (Regulation 2016/679) S3 plan-time
# assertions, mapped to the security-of-processing obligations (Art. 32) and
# records-of-processing (Art. 30).
#
# Framework-SPECIFIC. Structural hardening is in the generic `destroy` +
# `aws-s3-public-access` units; this adds only the GDPR plan-time `check` block.
# GDPR is mostly process/governance — the technical mappings here are the
# "security of processing" measures of Art. 32. Module binding:
# terraform-aws-modules/s3-bucket.

transform "new_block" gdpr_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_gdpr.tf"
  labels         = ["gdpr_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[GDPR Art.32(1)(a)] encryption of personal data at rest must be configured."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[GDPR Art.32(1)(b)] non-TLS transport must be denied to ensure confidentiality."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[GDPR Art.30 / Art.32(1)(d)] access logging must be enabled for records of processing and regular testing."
    }
  }
}
