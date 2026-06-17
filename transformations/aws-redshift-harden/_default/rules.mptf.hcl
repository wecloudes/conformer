# Transformation: aws-redshift-harden — HARD enforcement for Redshift clusters.
#
# Atomic, framework-agnostic, generic (any module). Forces encryption at rest
# and blocks public network exposure on every aws_redshift_cluster. Both are FLAT
# attributes on the resource, so they are overridden with asraw. Typed data
# source: an empty for_each (no matching resources) is a clean no-op.
#
# Control: CIS AWS Foundations / NIST 800-53 SC-28 (encryption at rest) and
# AC-4 / SC-7 (no publicly accessible data warehouse).

data "resource" redshift {
  resource_type = "aws_redshift_cluster"
}

transform "update_in_place" redshift_harden {
  for_each             = try(data.resource.redshift.result.aws_redshift_cluster, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    encrypted           = true
    publicly_accessible = false
  }
}
