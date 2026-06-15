# Model B (Terragrunt) — no registry. mapotf patches the downloaded module in
# the .terragrunt-cache working dir, in a before_hook, on every plan/apply.
#
# Putting the hook HERE (root.hcl) means every unit that includes it is patched
# automatically — a unit cannot silently opt out. If CI runs `terragrunt
# run-all` from this root, that is a real org-wide control (still weaker than
# the server-gated registry: someone can edit root.hcl).

locals {
  framework = "cis_v600"

  # Path to this repo's patches/ and scripts/. In a real git repo prefer
  # get_repo_root(); this relative form works even when not in a git checkout.
  repo_root = "${get_parent_terragrunt_dir()}/../../.."
}

terraform {
  # Patch the freshly-downloaded module copy before tofu/terraform runs.
  before_hook "compliance_patch" {
    commands = ["plan", "apply", "destroy"]
    execute = [
      "mapotf", "transform", "-r",
      "--mptf-dir", "${local.repo_root}/patches/${local.framework}/s3-bucket",
    ]
  }

  # Save a plan file so the gate can inspect it.
  extra_arguments "save_plan" {
    commands  = ["plan"]
    arguments = ["-out=tfplan"]
  }

  # Plan-time compliance gate (slide 29 layer 2). Fails the run on violation.
  after_hook "plan_gate" {
    commands     = ["plan"]
    execute      = ["${local.repo_root}/scripts/plan-gate.sh", "tfplan"]
    run_on_error = false
  }
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
