# Transformation: tags — ignore_changes = [tags] on every resource that HAS a
# tags attribute.
#
# Atomic, framework-agnostic, generic (any module). Tag drift (tags applied
# out-of-band by Azure Policy / org automation) stops forcing diffs. Resources
# without a `tags` attribute are left alone — ignore_changes on a non-existent
# attribute is a plan error. Composes with `destroy`: mapotf merges both
# lifecycle settings into one block (verified).
#
# NOTE: ignore_changes value is a quoted STRING ("[tags]"): mapotf asstring
# evaluates the RHS, so a bare [tags] is decoded as a variable. The string is
# emitted as raw HCL tokens → ignore_changes = [tags]. (Azure/mapotf idiom.)

variable "ignore_tag_changes" {
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
  tagged     = [for b in local.all_blocks : b.mptf.block_address if try(b.tags, null) != null]
}

transform "update_in_place" ignore_tag_changes {
  for_each             = try(toset(local.tagged), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      ignore_changes = var.ignore_tag_changes ? "[tags]" : "[]"
    }
  }
}
