# HIPAA Security Rule (45 CFR §164.312) — S3 Bucket Controls
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# HIPAA §164.312(a)(2)(iv) — Encryption and decryption
variable "hipaa_enforce_encryption" {
  type        = bool
  default     = true
  description = "[HIPAA §164.312(a)(2)(iv)] S3 bucket encryption at rest must be enabled"

  validation {
    condition     = var.hipaa_enforce_encryption == true
    error_message = "[HIPAA §164.312(a)(2)(iv)] S3 bucket server-side encryption must be enabled. Set server_side_encryption_configuration."
  }
}

# HIPAA §164.312(e)(2)(ii) — Encryption (transmission security)
variable "hipaa_enforce_ssl" {
  type        = bool
  default     = true
  description = "[HIPAA §164.312(e)(2)(ii)] Deny non-HTTPS access to S3 bucket"

  validation {
    condition     = var.hipaa_enforce_ssl == true
    error_message = "[HIPAA §164.312(e)(2)(ii)] S3 bucket policy must deny HTTP (non-SSL) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# HIPAA §164.312(b) — Audit controls
variable "hipaa_enforce_logging" {
  type        = bool
  default     = true
  description = "[HIPAA §164.312(b)] S3 bucket access logging must be enabled"

  validation {
    condition     = var.hipaa_enforce_logging == true
    error_message = "[HIPAA §164.312(b)] S3 bucket access logging must be configured. Set logging configuration."
  }
}
