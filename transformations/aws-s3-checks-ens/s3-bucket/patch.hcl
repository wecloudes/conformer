# Spain ENS (CCN) — S3 Bucket Controls
# Appended to the upstream terraform-aws-modules/s3-bucket module. Advisory
# toggles backing the ENS conformance-pack S3 rules (real RD 311/2022 codes).

# mp.info.3 — Cifrado de la información (encryption at rest)
variable "ens_enforce_encryption" {
  type        = bool
  default     = true
  description = "[ENS mp.info.3] S3 bucket encryption at rest must be enabled"

  validation {
    condition     = var.ens_enforce_encryption == true
    error_message = "[ENS mp.info.3] Cifrado de la información: set server_side_encryption_configuration."
  }
}

# mp.com.2 — Protección de la confidencialidad (TLS in transit)
variable "ens_enforce_ssl" {
  type        = bool
  default     = true
  description = "[ENS mp.com.2] Deny non-TLS access to S3 bucket"

  validation {
    condition     = var.ens_enforce_ssl == true
    error_message = "[ENS mp.com.2] Protección de la confidencialidad: enable attach_deny_insecure_transport_policy (deny non-TLS)."
  }
}

# op.exp.8 — Registro de la actividad (access logging)
variable "ens_enforce_logging" {
  type        = bool
  default     = true
  description = "[ENS op.exp.8] S3 bucket access logging must be enabled"

  validation {
    condition     = var.ens_enforce_logging == true
    error_message = "[ENS op.exp.8] Registro de la actividad: configure S3 access logging."
  }
}
