# Terragrunt catalog — plug hardened modules into a live infra repo

A small **catalog** of compliance-hardened modules, the shape you'd drop into a
real Terragrunt infrastructure repo. Each unit sources a module from the
Conformer registry via `tfr://`, so `terraform` runs unmodified and the
hardening is baked in + gated at the registry (Model A).

```
catalog/
├── root.hcl              # set the framework host ONCE; every unit inherits it
├── s3-bucket/            # hardened terraform-aws-modules/s3-bucket
│   └── terragrunt.hcl
└── vpc/                  # hardened terraform-aws-modules/vpc
    └── terragrunt.hcl
```

## Why this is "pluggable + accessible"

- **Pluggable:** the `source` is the only thing that differs from pulling the
  upstream module — same inputs, same outputs (guaranteed by the registry's
  interface check, `scripts/check-interface.sh`). Swap `tfr://cis.<host>/...`
  back to `tfr://registry.terraform.io/...` and nothing else changes.
- **Accessible:** standard Terragrunt — no custom plugins. Discover what the
  registry offers at `https://<host>/v1/catalog`.
- **Org-wide framework switch:** change `framework_host` in `root.hcl`
  (`cis` → `iso27001` → `soc2`) and `terragrunt run-all apply` re-pulls every
  unit hardened for the new framework.

## Run it

```bash
# dev: point *.conformer.local at localhost + trust the Caddy CA (compose/README)
# prod: use your real domain (docs/06-production-deployment.md)
terraform login cis.conformer.local        # or: export TG_TF_REGISTRY_TOKEN=<token>

cd s3-bucket && terragrunt init            # pulls the CIS-hardened module
terragrunt plan
# or from the catalog root:
terragrunt run-all plan
```

## Ad-hoc variant (open, no token)

For a quick, ungated pull (a framework bundle plus extra units), a unit can use
the go-getter direct source instead of `tfr://` — see
[`../model-b-mapotf/`](../model-b-mapotf/) and
[`../../direct-transform/`](../../direct-transform/):

```hcl
terraform {
  source = "https://<host>/m/terraform-aws-modules/s3-bucket/aws?version=4.1.2&framework=cis&transformation=tags,destroy"
}
```
