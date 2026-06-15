# CIS AWS Foundations Benchmark v6.0.0 — S3 Bucket Controls
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# CIS 2.1.1 — Ensure S3 bucket encryption is enabled
variable "cis_enforce_encryption" {
  type        = bool
  default     = true
  description = "[CIS 2.1.1] S3 bucket encryption must be enabled"

  validation {
    condition     = var.cis_enforce_encryption == true
    error_message = "[CIS 2.1.1] S3 bucket server-side encryption must be enabled. Set server_side_encryption_configuration."
  }
}

# CIS 2.1.2 — Ensure S3 bucket policy is set to deny HTTP requests
variable "cis_enforce_ssl_only" {
  type        = bool
  default     = true
  description = "[CIS 2.1.2] Deny non-HTTPS access to S3 bucket"

  validation {
    condition     = var.cis_enforce_ssl_only == true
    error_message = "[CIS 2.1.2] S3 bucket policy must deny HTTP (non-SSL) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# CIS 2.1.3 — Ensure MFA Delete is enabled on S3 buckets
variable "cis_enforce_versioning" {
  type        = bool
  default     = true
  description = "[CIS 2.1.3] S3 bucket versioning must be enabled"

  validation {
    condition     = var.cis_enforce_versioning == true
    error_message = "[CIS 2.1.3] S3 bucket versioning must be enabled for MFA Delete support."
  }
}

# CIS 2.1.4 — Ensure S3 bucket access logging is enabled
variable "cis_enforce_logging" {
  type        = bool
  default     = true
  description = "[CIS 2.1.4] S3 bucket access logging must be enabled"

  validation {
    condition     = var.cis_enforce_logging == true
    error_message = "[CIS 2.1.4] S3 bucket access logging must be configured. Set logging configuration."
  }
}

# CIS 3.3 — Ensure public access is blocked
variable "cis_block_public_access" {
  type        = bool
  default     = true
  description = "[CIS 3.3] Block all public access to S3 bucket"

  validation {
    condition     = var.cis_block_public_access == true
    error_message = "[CIS 3.3] All public access must be blocked. Set block_public_acls, block_public_policy, ignore_public_acls, restrict_public_buckets to true."
  }
}
