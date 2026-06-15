# Smoke test for the running Docker Compose registry (Model A, dynamic build).
# Pulls the CIS-hardened Azure automation-account module straight from the local
# registry. Requires:
#   - the compose stack up (compose/docker-compose.yml)
#   - the Caddy CA trusted on the host
#   - *.conformer.local in /etc/hosts (see compose/README.md)
#   - export TF_TOKEN_cis_conformer_local=dev-token-changeme
#
#   terraform init      # downloads the patched module from the registry
#   terraform providers # shows the module resolved

terraform {
  required_version = ">= 1.5"
}

module "automation" {
  source  = "cis.conformer.local/Azure/avm-res-automation-automationaccount/azurerm"
  version = "0.2.0"

  # Minimal inputs — we only need `terraform init`/`get` to resolve + unpack the
  # hardened module from the registry, not a full plan (needs Azure creds).
  name                = "smoke-aa"
  resource_group_name = "rg-smoke"
  location            = "westeurope"
}
