# Azure Verified Modules (avm-res-*) family pack — secure defaults.
#
# AVM standardizes its input interface, so these variable names are the same in
# every AVM module. Each override is GUARDED by a presence check (data.variable)
# so this file is a safe no-op on non-AVM / AWS modules — mapotf would otherwise
# error on a missing target_block_address.
#
# These are SOFT defaults (a caller can still pass a value). For absolute
# enforcement pair with a plan-time assert (see docs/05-transformation-catalog).
#
#   enable_telemetry              -> false  (privacy; also count-gates the
#                                            modtm_telemetry/random_uuid resources)
#   local_authentication_enabled  -> false  (force Entra ID, disable shared keys)
#   public_network_access_enabled -> false  (private by default)

data "variable" all {
}

locals {
  avm_secure_false = [
    "enable_telemetry",
    "local_authentication_enabled",
    "public_network_access_enabled",
  ]
  avm_present = [
    for v in local.avm_secure_false : v
    if contains(keys(try(data.variable.all.result, {})), v)
  ]
}

transform "update_in_place" avm_secure_defaults {
  for_each             = try(toset(local.avm_present), [])
  target_block_address = "variable.${each.value}"
  asraw {
    default = false
  }
}
