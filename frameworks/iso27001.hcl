# Framework manifest — ISO/IEC 27001:2022 (Annex A controls).
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). Differs from
# CIS only in the S3 plan-time checks (A.8.24 requires KMS). All structural
# units are shared. Keep `transformations` a flat list of quoted unit names.

description = "ISO/IEC 27001:2022"

transformations = [
  "avm-secure-defaults",
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-iso27001",
  "aws-rds-harden",
  "aws-eks-audit-logs",
  "aws-vpc-flow-logs",
]
