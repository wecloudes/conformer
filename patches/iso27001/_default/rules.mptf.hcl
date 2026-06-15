# iso27001 — GENERIC rules applied to ANY module pulled through the registry.
#
# Module-agnostic controls only (no resource-type assumptions), so this hardens
# modules that have no module-specific rules file. Module-specific rules in
# patches/iso27001/<module>/ layer on top.
#
# Controls:
#   - prevent_destroy on every managed resource (lifecycle meta-arg, valid on all).
#   - ignore_changes = [tags] on every resource that HAS a tags attribute, so
#     tag drift (e.g. tags applied out-of-band by Azure Policy / org automation)
#     does not force diffs. Resources without `tags` are left alone — adding
#     ignore_changes for a non-existent attribute is a plan error.
#
# A single lifecycle block is emitted per resource (tagged resources get both
# settings) so we never produce a duplicate lifecycle block.

variable "prevent_destroy" {
  type    = bool
  default = true
}

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

  # Split resources by whether they declare a `tags` attribute.
  tagged   = [for b in local.all_blocks : b.mptf.block_address if try(b.tags, null) != null]
  untagged = [for b in local.all_blocks : b.mptf.block_address if try(b.tags, null) == null]
}

# Tagged resources: protect from destroy AND ignore tag drift.
transform "update_in_place" harden_tagged {
  for_each             = try(toset(local.tagged), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
      # asstring emits the string value as raw HCL tokens, so "[tags]" becomes
      # the list [tags] (not a quoted string).
      ignore_changes = var.ignore_tag_changes ? "[tags]" : "[]"
    }
  }
}

# Untagged resources: protect from destroy only.
transform "update_in_place" harden_untagged {
  for_each             = try(toset(local.untagged), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
    }
  }
}
