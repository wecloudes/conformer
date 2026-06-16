# Catalog root — shared config for every hardened-module unit below.
#
# The framework is the registry SUBDOMAIN. Set it once; every unit that
# `include`s this file inherits it. Switch the whole catalog to another
# framework by changing this one value (cis -> iso27001 -> soc2).
#
# Auth (the registry checks Bearer token + framework entitlement):
#   terraform login cis.conformer.local        # writes credentials.tfrc.json
#   export TG_TF_REGISTRY_TOKEN=<token>          # or this env var
#
# In production, set framework_host to your real domain
# (e.g. cis.conformer.example.com) — see docs/06-production-deployment.md.

locals {
  framework_host = "cis.conformer.local"
}

# A real repo would configure remote_state here (S3 + DynamoDB lock); omitted so
# the example plans with a local backend.
# remote_state {
#   backend = "s3"
#   ...
# }

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "aws" {
      region = "eu-west-1"
    }
  EOF
}
