# Direct (go-getter) mode — framework-less, ad-hoc transformation set (ADR-009).
#
# No framework, no token, no entitlement. The transformation set rides a real
# query string on a go-getter HTTP source (NOT a registry source), so:
#   - the source is a full https:// URL,
#   - there is NO `version =` argument (that is registry-only) — the version is
#     a query param the registry reads,
#   - the server resolves ?transformation=, builds tags+destroy ONLY, caches it
#     under a canonical profile key, and returns X-Terraform-Get -> the zip.
#
# Requires:
#   - the compose stack up (compose/docker-compose.yml), DIRECT_MODE=true (default)
#   - Caddy CA trusted on the host
#   - APEX in /etc/hosts:  127.0.0.1 conformer.local
#     (in addition to the *.conformer.local subdomains from compose/README.md)
#
#   terraform init        # downloads the patched module from the direct endpoint
#   grep -rn ignore_changes .terraform/modules/   # proof the transforms landed

terraform {
  required_version = ">= 1.5"
}

module "automation" {
  # go-getter http source: version + transformation set in the query string.
  source = "https://conformer.local/m/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0&transformation=tags,destroy"

  # Or compose a whole framework bundle PLUS extra ad-hoc units (still open):
  #   source = "https://conformer.local/m/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0&framework=cis&transformation=tags,destroy"
  # framework= expands its unit bundle; the transformation= units apply on top.

  # Minimal inputs to satisfy the module's required arguments. A full `plan`
  # would also need a configured azurerm provider + Azure creds; this example
  # only proves the registry serves the patched module (init/get resolves it).
  name                = "smoke-aa"
  resource_group_name = "rg-smoke"
  location            = "westeurope"
  sku                 = "Basic"
}
