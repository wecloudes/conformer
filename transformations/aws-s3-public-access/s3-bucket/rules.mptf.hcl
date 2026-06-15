# Transformation: aws-s3-public-access — force-block ALL public access on
# aws_s3_bucket_public_access_block, overriding any caller value.
#
# Atomic structural unit, framework-agnostic (CIS 3.3 / ISO A.8.3 / SOC2 CC6.1
# all require this identically). Module binding: terraform-aws-modules/s3-bucket.
# prevent_destroy is intentionally NOT here — the generic `destroy` unit covers
# every resource including the bucket.

data "resource" pab {
  resource_type = "aws_s3_bucket_public_access_block"
}

transform "update_in_place" block_public_access {
  for_each             = try(data.resource.pab.result.aws_s3_bucket_public_access_block, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}
