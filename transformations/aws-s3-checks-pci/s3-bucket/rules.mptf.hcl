# Transformation: aws-s3-checks-pci — PCI DSS v4.0 S3 plan-time assertions.
#
# Framework-SPECIFIC (the control thresholds differ per framework), so this unit
# is named per framework. Structural hardening (prevent_destroy, block public
# access) lives in the generic `destroy` + `aws-s3-public-access` units; this one
# only adds the PCI DSS plan-time `check` block that the jq plan-gate turns into a
# CI failure. Module binding: terraform-aws-modules/s3-bucket.

transform "new_block" pci_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_pci_dss.tf"
  labels         = ["pci_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[PCI DSS 3.5.1] stored data must be rendered unreadable via strong cryptography; server_side_encryption_configuration must be set."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[PCI DSS 4.2.1] strong cryptography (TLS) must protect data over open networks; attach_deny_insecure_transport_policy must be true (deny non-TLS)."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[PCI DSS 10.2.1] audit logs must be enabled; access logging must be configured."
    }
  }
}
