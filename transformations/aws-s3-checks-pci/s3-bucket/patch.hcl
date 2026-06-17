# PCI DSS v4.0 — S3 Bucket Controls
# These blocks are appended to the upstream terraform-aws-modules/s3-bucket module.

# PCI DSS 3.5.1 — Render stored data unreadable via strong cryptography
variable "pci_enforce_encryption" {
  type        = bool
  default     = true
  description = "[PCI DSS 3.5.1] S3 bucket encryption at rest must be enabled"

  validation {
    condition     = var.pci_enforce_encryption == true
    error_message = "[PCI DSS 3.5.1] Stored data must be rendered unreadable using strong cryptography. Set server_side_encryption_configuration."
  }
}

# PCI DSS 4.2.1 — Strong cryptography (TLS) for data over open networks
variable "pci_enforce_ssl" {
  type        = bool
  default     = true
  description = "[PCI DSS 4.2.1] Deny non-TLS access to S3 bucket"

  validation {
    condition     = var.pci_enforce_ssl == true
    error_message = "[PCI DSS 4.2.1] S3 bucket policy must deny non-TLS (insecure transport) requests. Enable attach_deny_insecure_transport_policy."
  }
}

# PCI DSS 10.2.1 — Audit logs enabled and active
variable "pci_enforce_logging" {
  type        = bool
  default     = true
  description = "[PCI DSS 10.2.1] S3 bucket access logging must be enabled"

  validation {
    condition     = var.pci_enforce_logging == true
    error_message = "[PCI DSS 10.2.1] S3 bucket audit/access logging must be configured. Set logging configuration."
  }
}
