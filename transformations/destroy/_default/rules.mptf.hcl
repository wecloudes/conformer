# Transformation: destroy — prevent_destroy on EVERY managed resource.
#
# Atomic, framework-agnostic, generic (any module). lifecycle.prevent_destroy is
# a meta-argument valid on all resource types, so this needs no resource-type
# knowledge. Composes with `tags`: mapotf update_in_place merges both into a
# single lifecycle block (verified), so selecting destroy+tags never produces a
# duplicate lifecycle block.

variable "prevent_destroy" {
  type    = bool
  default = true
}

data "resource" all_resource {
}

locals {
  all_resource_blocks = flatten([
    for resource_type, resource_blocks in data.resource.all_resource.result : resource_blocks
  ])
  all_blocks = flatten([for _, blocks in local.all_resource_blocks : [for b in blocks : b]])
  all_addrs  = [for b in local.all_blocks : b.mptf.block_address]
}

transform "update_in_place" prevent_destroy {
  for_each             = try(toset(local.all_addrs), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
    }
  }
}
