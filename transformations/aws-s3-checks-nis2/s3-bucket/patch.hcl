# NIS2 Directive (EU 2022/2555) — S3 Bucket Controls
# Mapped to Art.21(2) cybersecurity risk-management measures and Art.23 reporting.
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# NIS2 Art.21(2)(h) — Cryptography and encryption (at rest)
variable "nis2_enforce_encryption" {
  type        = bool
  default     = true
  description = "[NIS2 Art.21(2)(h)] S3 bucket encryption at rest must be enabled (cryptography and encryption)"

  validation {
    condition     = var.nis2_enforce_encryption == true
    error_message = "[NIS2 Art.21(2)(h)] S3 bucket server-side encryption must be enabled. Set server_side_encryption_configuration."
  }
}

# NIS2 Art.21(2)(h) — Cryptography and encryption (in transit)
variable "nis2_enforce_ssl_only" {
  type        = bool
  default     = true
  description = "[NIS2 Art.21(2)(h)] Deny non-HTTPS access to S3 bucket (cryptography — in transit)"

  validation {
    condition     = var.nis2_enforce_ssl_only == true
    error_message = "[NIS2 Art.21(2)(h)] S3 bucket policy must deny HTTP (non-TLS) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# NIS2 Art.21(2)(b) / Art.23 — Incident handling and reporting
variable "nis2_enforce_logging" {
  type        = bool
  default     = true
  description = "[NIS2 Art.21(2)(b) / Art.23] S3 bucket access logging must be enabled for incident handling and reporting"

  validation {
    condition     = var.nis2_enforce_logging == true
    error_message = "[NIS2 Art.21(2)(b) / Art.23] S3 bucket access logging must be configured. Set logging configuration."
  }
}
