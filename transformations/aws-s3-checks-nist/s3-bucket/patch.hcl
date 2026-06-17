# NIST SP 800-53 Rev 5 — S3 Bucket Controls
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# SC-28 — Protection of Information at Rest
variable "nist_enforce_encryption" {
  type        = bool
  default     = true
  description = "[NIST SC-28] S3 bucket encryption at rest must be enabled"

  validation {
    condition     = var.nist_enforce_encryption == true
    error_message = "[NIST SC-28] S3 bucket server-side encryption must be enabled. Set server_side_encryption_configuration."
  }
}

# SC-8 / SC-13 — Transmission Confidentiality and Integrity / Cryptographic Protection
variable "nist_enforce_ssl" {
  type        = bool
  default     = true
  description = "[NIST SC-8] Deny non-HTTPS access to S3 bucket"

  validation {
    condition     = var.nist_enforce_ssl == true
    error_message = "[NIST SC-8] S3 bucket policy must deny HTTP (non-SSL) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# AU-2 / AU-12 — Event Logging / Audit Record Generation
variable "nist_enforce_logging" {
  type        = bool
  default     = true
  description = "[NIST AU-2] S3 bucket access logging must be enabled"

  validation {
    condition     = var.nist_enforce_logging == true
    error_message = "[NIST AU-2] S3 bucket access logging must be configured. Set logging configuration."
  }
}
