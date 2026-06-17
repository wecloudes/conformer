# Transformation: aws-s3-checks-ens — Spain ENS (CCN) S3 plan-time assertions.
#
# Framework-SPECIFIC: backs the S3 controls of the AWS Config CCN-ENS conformance
# packs (Operational-Best-Practices-for-CCN-ENS-{Low,Medium,High}) — shared by all
# three ENS levels, since the S3 rules are identical across them. Structural
# hardening (prevent_destroy, block public access) lives in the generic `destroy`
# + `aws-s3-public-access` units; this one adds the ENS plan-time `check` block the
# jq plan-gate turns into a CI failure. Module binding: terraform-aws-modules/s3-bucket.
#
# Mapped Config rules -> real ENS RD 311/2022 Annex II measure codes:
#   S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED -> mp.info.3 (Cifrado de la información)
#   S3_BUCKET_SSL_REQUESTS_ONLY              -> mp.com.2 (Protección de la confidencialidad)
#   S3_BUCKET_LOGGING_ENABLED                -> op.exp.8 (Registro de la actividad)

transform "new_block" ens_plan_checks {
  new_block_type = "check"
  filename       = "_compliance_ens.tf"
  labels         = ["ens_s3_controls"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[ENS mp.info.3] Cifrado de la información: server_side_encryption_configuration must be set (S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED)."
    }
    assert {
      condition     = try(var.attach_deny_insecure_transport_policy, false) == true
      error_message = "[ENS mp.com.2] Protección de la confidencialidad: attach_deny_insecure_transport_policy must be true to deny non-TLS access (S3_BUCKET_SSL_REQUESTS_ONLY)."
    }
    assert {
      condition     = length(keys(var.logging)) > 0
      error_message = "[ENS op.exp.8] Registro de la actividad: S3 access logging must be configured (S3_BUCKET_LOGGING_ENABLED)."
    }
  }
}
