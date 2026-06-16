# Terragrunt integration

Two ways to consume compliance-hardened modules from Terragrunt. Both reuse the
same compliance content — the transformation units bundled by
`frameworks/<framework>.hcl` (e.g. `transformations/aws-s3-public-access/s3-bucket/`).

```
model-a-registry/        # pull hardened module via tfr:// (server-gated)
  root.hcl               #   framework = registry subdomain
  s3-bucket/terragrunt.hcl
model-b-mapotf/          # patch upstream locally via before_hook (no registry)
  root.hcl               #   org-wide mapotf hook + plan-gate
  s3-bucket/terragrunt.hcl
catalog/                 # a multi-unit catalog of hardened modules (drop-in)
  root.hcl               #   framework host, shared by every unit
  s3-bucket/terragrunt.hcl
  vpc/terragrunt.hcl
```

## Model A — registry (`tfr://`)

Enforcement is mandatory and server-gated; `terraform` runs unmodified.

```bash
cd model-a-registry/s3-bucket
terraform login cis.conformer.local      # or: export TG_TF_REGISTRY_TOKEN=...
terragrunt plan
```

- Framework = the subdomain in `root.hcl` (`framework_host`). Switch it to
  `iso27001.conformer.local` / `soc2.conformer.local` to change framework
  org-wide.
- Needs **Terragrunt ≥ 1.0.5** if `TG_PROVIDER_CACHE` is on (older versions send
  the cache key instead of your token → `403 Forbidden`).

## Model B — direct mapotf (`before_hook`)

No registry / fork. The `before_hook` in `root.hcl` runs `mapotf transform`
against the module Terragrunt downloads into `.terragrunt-cache/`, then a
`plan_gate` after_hook fails the run on violation.

```bash
cd model-b-mapotf/s3-bucket
# needs: mapotf, terraform, jq on PATH
terragrunt plan
```

- The hook lives in `root.hcl`, so every unit including it is patched — a unit
  cannot opt out. Run `terragrunt run-all plan` from the root in CI to enforce
  across all units.
- Opt-in at the org boundary, not a hard control (root.hcl is editable). Use
  Model A when consumers are untrusted.

## Which?

| Need | Model |
|---|---|
| Mandatory, untrusted consumers, entitlement gate | **A** (`tfr://`) |
| No registry infra, internal teams | **B** (`before_hook` in root.hcl) |
| Defense in depth | A for source + B's `plan_gate` after_hook as drift catch |
