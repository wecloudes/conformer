# Transformation: aws-s3-checks-soc2 — SOC 2 Type II S3 plan-time assertions,
# mapped to Trust Services Criteria (CC6.1 / CC6.7 / CC7.2 / A1.2).
#
# Framework-SPECIFIC. Structural hardening is in the generic `destroy` +
# `aws-s3-public-access` units; this adds only the SOC2 plan-time `check` block.
# Module binding: terraform-aws-modules/s3-bucket.

transform "new_block" soc2_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_soc2.tf"
  labels         = ["soc2_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[SOC2 CC6.1] encryption at rest must be configured."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[SOC2 CC6.7] non-TLS transport must be denied."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[SOC2 CC7.2] access logging must be enabled for monitoring."
    }
    assert {
      condition     = length(keys(var.replication_configuration)) > 0
      error_message = "[SOC2 A1.2 Advisory] consider cross-region replication for availability."
    }
  }
}
