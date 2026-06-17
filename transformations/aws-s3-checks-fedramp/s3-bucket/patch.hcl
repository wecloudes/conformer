# FedRAMP (NIST SP 800-53 baseline) — S3 Bucket Controls
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# SC-28 — Protection of Information at Rest
variable "fedramp_enforce_encryption" {
  type        = bool
  default     = true
  description = "[FedRAMP SC-28] S3 bucket encryption at rest must be enabled"

  validation {
    condition     = var.fedramp_enforce_encryption == true
    error_message = "[FedRAMP SC-28] S3 bucket server-side encryption must be enabled. Set server_side_encryption_configuration."
  }
}

# SC-8 / SC-13 — Transmission Confidentiality and Integrity / Cryptographic Protection
variable "fedramp_enforce_ssl" {
  type        = bool
  default     = true
  description = "[FedRAMP SC-8 / SC-13] Deny non-TLS access to S3 bucket"

  validation {
    condition     = var.fedramp_enforce_ssl == true
    error_message = "[FedRAMP SC-8 / SC-13] S3 bucket policy must deny non-TLS (HTTP) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# AU-2 — Event Logging
variable "fedramp_enforce_logging" {
  type        = bool
  default     = true
  description = "[FedRAMP AU-2] S3 bucket access logging must be enabled"

  validation {
    condition     = var.fedramp_enforce_logging == true
    error_message = "[FedRAMP AU-2] S3 bucket access logging must be configured. Set logging configuration."
  }
}
