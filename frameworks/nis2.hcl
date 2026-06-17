# Framework manifest — NIS2 Directive (EU 2022/2555).
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). The build
# pipeline expands this list and applies each unit from transformations/<name>/.
# Units that have no rules for the module being built are simply skipped, so the
# same bundle hardens any module (generic units) plus the modules it has bindings
# for (aws-* units). Keep `transformations` a flat list of quoted unit names.

description = "NIS2 Directive (EU 2022/2555) — Art.21 risk-management measures"

transformations = [
  "avm-secure-defaults",
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-nis2",
  "aws-rds-harden",
  "aws-eks-audit-logs",
  "aws-vpc-flow-logs",
]
