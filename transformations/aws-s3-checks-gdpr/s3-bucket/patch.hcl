# GDPR (Regulation 2016/679) — S3 Bucket Controls (security of processing)
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# GDPR Art. 32(1)(a) — Encryption of personal data
variable "gdpr_enforce_encryption" {
  type        = bool
  default     = true
  description = "[GDPR Art.32(1)(a)] S3 bucket encryption of personal data at rest must be enabled"

  validation {
    condition     = var.gdpr_enforce_encryption == true
    error_message = "[GDPR Art.32(1)(a)] S3 bucket server-side encryption must be enabled. Set server_side_encryption_configuration."
  }
}

# GDPR Art. 32(1)(b) — Ensure ongoing confidentiality (deny non-TLS access)
variable "gdpr_enforce_ssl" {
  type        = bool
  default     = true
  description = "[GDPR Art.32(1)(b)] Deny non-HTTPS access to S3 bucket to ensure confidentiality"

  validation {
    condition     = var.gdpr_enforce_ssl == true
    error_message = "[GDPR Art.32(1)(b)] S3 bucket policy must deny HTTP (non-SSL) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# GDPR Art. 30 / Art. 32(1)(d) — Records of processing & regular testing
variable "gdpr_enforce_logging" {
  type        = bool
  default     = true
  description = "[GDPR Art.30 / Art.32(1)(d)] S3 bucket access logging must be enabled for records of processing"

  validation {
    condition     = var.gdpr_enforce_logging == true
    error_message = "[GDPR Art.30 / Art.32(1)(d)] S3 bucket access logging must be configured. Set logging configuration."
  }
}
