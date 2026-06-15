# SOC 2 Type II — S3 Bucket Controls
# Mapped to Trust Services Criteria (TSC)

# CC6.1 — Logical and Physical Access Controls (block public access)
variable "soc2_block_public_access" {
  type        = bool
  default     = true
  description = "[SOC2 CC6.1] Public access must be blocked"

  validation {
    condition     = var.soc2_block_public_access == true
    error_message = "[SOC2 CC6.1] All S3 public access must be blocked to satisfy logical access control requirements."
  }
}

# CC6.1 — Encryption at rest
variable "soc2_enforce_encryption" {
  type        = bool
  default     = true
  description = "[SOC2 CC6.1] Encryption at rest is required"

  validation {
    condition     = var.soc2_enforce_encryption == true
    error_message = "[SOC2 CC6.1] S3 bucket must have server-side encryption enabled."
  }
}

# CC6.7 — Restrict transmission to authorized parties (SSL only)
variable "soc2_enforce_ssl" {
  type        = bool
  default     = true
  description = "[SOC2 CC6.7] Only encrypted transport (HTTPS) is allowed"

  validation {
    condition     = var.soc2_enforce_ssl == true
    error_message = "[SOC2 CC6.7] S3 bucket must deny non-SSL requests to ensure encrypted data transmission."
  }
}

# CC7.2 — System monitoring (access logging)
variable "soc2_enforce_logging" {
  type        = bool
  default     = true
  description = "[SOC2 CC7.2] Access logging must be enabled for monitoring"

  validation {
    condition     = var.soc2_enforce_logging == true
    error_message = "[SOC2 CC7.2] S3 bucket access logging must be enabled for system monitoring and anomaly detection."
  }
}

# CC8.1 — Change management (versioning)
variable "soc2_enforce_versioning" {
  type        = bool
  default     = true
  description = "[SOC2 CC8.1] Object versioning required for change tracking"

  validation {
    condition     = var.soc2_enforce_versioning == true
    error_message = "[SOC2 CC8.1] S3 bucket versioning must be enabled to support change management and rollback capabilities."
  }
}

# A1.2 — Availability (cross-region replication recommendation)
check "soc2_replication_advisory" {
  assert {
    condition     = true
    error_message = "[SOC2 A1.2 Advisory] Consider enabling cross-region replication for availability requirements."
  }
}
