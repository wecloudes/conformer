# Framework manifest — FedRAMP (NIST SP 800-53 baseline).
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). The build
# pipeline expands this list and applies each unit from transformations/<name>/.
# Units that have no rules for the module being built are simply skipped, so the
# same bundle hardens any module (generic units) plus the modules it has bindings
# for (aws-* units). Keep `transformations` a flat list of quoted unit names.

description = "FedRAMP (NIST SP 800-53 baseline)"

transformations = [
  "avm-secure-defaults",
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-fedramp",
  "aws-rds-harden",
  "aws-eks-audit-logs",
  "aws-vpc-flow-logs",
]
