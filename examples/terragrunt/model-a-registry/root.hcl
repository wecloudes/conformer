# Model A (Terragrunt) — pull compliance-hardened modules from the registry.
#
# The framework is the registry SUBDOMAIN. Set it once here; every unit that
# `include`s this file inherits it. Switch frameworks org-wide by changing this
# one value (cis -> iso27001 -> soc2 ...).
#
# Auth (the Go registry API checks Bearer token + framework entitlement):
#   terraform login cis.conformer.local        # writes credentials.tfrc.json
#   export TG_TF_REGISTRY_TOKEN=<token>          # or this env var
#
# Requires Terragrunt >= 1.0.5 if TG_PROVIDER_CACHE is enabled (older versions
# send the cache key instead of your token -> 403 Forbidden).

locals {
  framework_host = "cis.conformer.local"
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "eu-west-1"
    }
  EOF
}
