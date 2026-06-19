# Framework manifest — tags only.
#
# A framework is a NAMED BUNDLE of transformation units (ADR-009). This one is
# the single `tags` unit: it appends `lifecycle { ignore_changes = [tags] }` to
# every resource that has a `tags` attribute. No secure-defaults, no
# `prevent_destroy`, no resource changes — purely stops tag drift on existing
# resources. Exposes the ad-hoc `?transformation=tags` set over the registry
# protocol (tfr://tags.<DOMAIN>/...) so Terragrunt can consume it as a root
# module. Keep `transformations` a flat list of quoted unit names.

description = "Tags only — ignore_changes = [tags]"

transformations = [
  "tags",
]
