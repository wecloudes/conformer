# Transformation: aws-s3-checks-hipaa — HIPAA Security Rule S3 plan-time
# assertions, mapped to the technical safeguards in 45 CFR §164.312.
#
# Framework-SPECIFIC. Structural hardening is in the generic `destroy` +
# `aws-s3-public-access` units; this adds only the HIPAA plan-time `check` block.
# Module binding: terraform-aws-modules/s3-bucket.

transform "new_block" hipaa_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_hipaa.tf"
  labels         = ["hipaa_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[HIPAA §164.312(a)(2)(iv) Encryption and decryption] encryption at rest must be configured."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[HIPAA §164.312(e)(2)(ii) Encryption] non-TLS transport must be denied (transmission security)."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[HIPAA §164.312(b) Audit controls] access logging must be configured."
    }
  }
}
