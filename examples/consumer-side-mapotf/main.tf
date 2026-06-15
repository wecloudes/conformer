# Model B — direct consumer-side patching with mapotf. No registry, no fork.
#
# The module is sourced from a LOCAL checkout of the real upstream module
# (./upstream, fetched by harden.sh). mapotf rewrites that checkout in place at
# plan time; `mapotf reset` restores it afterwards. The upstream repo is never
# forked and nothing is pushed to a registry.
#
# This config is deliberately NON-compliant (public access not locked, no
# encryption) so you can watch the transforms + plan-gate catch it.

terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region                      = "eu-west-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
}

module "s3_bucket" {
  source = "./upstream"

  bucket = "demo-consumer-side-bucket"

  # Caller leaves these open on purpose — mapotf forces them shut, and the
  # plan-gate fails the build if encryption/versioning are still missing.
  attach_public_policy = false
}
