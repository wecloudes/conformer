# Framework manifest — SOC 2 Type II (Trust Services Criteria).
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). Differs from
# CIS only in the S3 plan-time checks (adds A1.2 replication advisory). All
# structural units are shared. Keep `transformations` a flat list of quoted
# unit names.

description = "SOC 2 Type II"

transformations = [
  "avm-secure-defaults",
  "aws-secure-defaults",
  "destroy",
  "tags",
  "aws-s3-public-access",
  "aws-s3-checks-soc2",
  "aws-rds-harden",
  "aws-eks-audit-logs",
  "aws-vpc-flow-logs",
]
