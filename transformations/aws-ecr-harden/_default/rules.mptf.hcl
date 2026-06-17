# GENERIC enforcement: ECR repository hardening — immutable tags + scan on push.
#
# Applies to ANY module declaring an aws_ecr_repository. The typed query matches
# by resource_type, so an empty result (module has no such resource) is a no-op.
# image_tag_mutability is a flat attribute (asraw); image_scanning_configuration
# is a nested block (asstring). Both transforms share the same for_each so they
# patch the same resource in a single pass.

data "resource" ecr {
  resource_type = "aws_ecr_repository"
}

transform "update_in_place" ecr_immutable_tags {
  for_each             = try(data.resource.ecr.result.aws_ecr_repository, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    image_tag_mutability = "IMMUTABLE"
  }
}

transform "update_in_place" ecr_scan_on_push {
  for_each             = try(data.resource.ecr.result.aws_ecr_repository, {})
  target_block_address = each.value.mptf.block_address
  asstring {
    image_scanning_configuration {
      scan_on_push = true
    }
  }
}
