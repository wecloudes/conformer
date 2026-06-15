# ISO 27001:2022 — S3 Bucket Controls
# Mapped to Annex A controls from ISO/IEC 27001:2022

# A.8.10 — Information deletion (lifecycle policies)
variable "iso27001_enforce_lifecycle" {
  type        = bool
  default     = true
  description = "[ISO27001 A.8.10] Lifecycle policies must be configured for data retention"

  validation {
    condition     = var.iso27001_enforce_lifecycle == true
    error_message = "[ISO27001 A.8.10] S3 bucket must have lifecycle rules configured to enforce data retention and deletion policies."
  }
}

# A.8.24 — Use of cryptography (encryption at rest)
variable "iso27001_enforce_encryption" {
  type        = bool
  default     = true
  description = "[ISO27001 A.8.24] Encryption at rest must be enabled with KMS"

  validation {
    condition     = var.iso27001_enforce_encryption == true
    error_message = "[ISO27001 A.8.24] S3 bucket must use KMS encryption (not AES256). Configure server_side_encryption_configuration with aws:kms."
  }
}

# A.8.3 — Information access restriction (block public access)
variable "iso27001_block_public_access" {
  type        = bool
  default     = true
  description = "[ISO27001 A.8.3] Public access must be restricted"

  validation {
    condition     = var.iso27001_block_public_access == true
    error_message = "[ISO27001 A.8.3] All public access must be blocked to comply with information access restriction requirements."
  }
}

# A.8.15 — Logging (access logging)
variable "iso27001_enforce_logging" {
  type        = bool
  default     = true
  description = "[ISO27001 A.8.15] Access logging must be enabled"

  validation {
    condition     = var.iso27001_enforce_logging == true
    error_message = "[ISO27001 A.8.15] S3 bucket access logging must be enabled for audit trail requirements."
  }
}

# A.8.25 — Secure development lifecycle (versioning for integrity)
variable "iso27001_enforce_versioning" {
  type        = bool
  default     = true
  description = "[ISO27001 A.8.25] Object versioning must be enabled for data integrity"

  validation {
    condition     = var.iso27001_enforce_versioning == true
    error_message = "[ISO27001 A.8.25] S3 bucket versioning must be enabled to protect data integrity."
  }
}

# A.8.24 — Encryption in transit (SSL-only policy)
variable "iso27001_enforce_ssl" {
  type        = bool
  default     = true
  description = "[ISO27001 A.8.24] Only HTTPS access must be allowed"

  validation {
    condition     = var.iso27001_enforce_ssl == true
    error_message = "[ISO27001 A.8.24] S3 bucket must enforce SSL/TLS for all requests. Enable attach_deny_insecure_transport_policy."
  }
}
