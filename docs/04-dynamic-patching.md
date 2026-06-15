# Dynamic (on-demand) patching

By default the registry serves modules that were patched ahead of time (Tekton
or `compose/build.sh`). **Dynamic patching** removes that step: request *any*
module through the registry and it is fetched from the upstream Terraform
registry, patched for the framework in the subdomain, cached, and served — the
first time it is asked for.

```hcl
# Terragrunt — any upstream module, hardened for the subdomain's framework
terraform {
  source = "tfr://${include.root.locals.framework_host}/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0"
}
```

With `framework_host = "cis.conformer.local"`, that single source:

1. resolves to the registry (subdomain → framework `cis_v600`)
2. on cache miss, the API fetches `Azure/avm-res-automation-automationaccount/azurerm`
   `0.2.0` from `registry.terraform.io`
3. applies the CIS rules and serves the hardened zip — no pre-build, no entry in
   `patches/` required for that specific module

## How it works

```
terraform init
   │  GET …/versions          ─► API proxies registry.terraform.io versions
   │                              (so any version is resolvable)
   │  GET …/{version}/download
   ▼
API handleDownload
   ├─ object in MinIO?  ── yes ─► presigned URL (X-Terraform-Get)
   └─ no  ─► ensureBuilt()
              ├─ lock per object key (dedupe concurrent requests)
              ├─ scripts/build-dynamic.sh ns name provider version framework
              │     • tofu get             → pull module (modules only, no providers)
              │     • scripts/patch-module.sh → generic + module-specific layers
              │     • (API uploads the zip via the minio-go SDK)
              └─ presigned URL  → {…}/{framework}/{version}.zip
```

Subsequent requests for the same `(module, version, framework)` hit the MinIO
cache directly. Implementation: `registry-api/build.go`
(`ensureBuilt`, `fetchUpstreamVersions`) and `scripts/build-dynamic.sh`.

## Generic vs module-specific rules

Dynamic patching works on modules that have **no** entry in `patches/` because
each framework ships a **generic** rule set applied to every module:

```
patches/<framework>/_default/rules.mptf.hcl   # applied to ANY module
patches/<framework>/<module>/rules.mptf.hcl   # layered on top when present
```

`scripts/patch-module.sh` applies `_default` first, then the module-specific
rules if they exist. The generic layer uses module-agnostic transforms:

- **`prevent_destroy`** on every managed resource (a lifecycle meta-argument
  valid on all resource types).
- **`ignore_changes = [tags]`** on every resource that *has* a `tags` attribute,
  so tag drift (tags applied out-of-band by org automation / Azure Policy) does
  not force diffs.

Resources are split into tagged / untagged so a single lifecycle block is
emitted per resource (no duplicate `lifecycle` block), and `ignore_changes` is
never added to a resource that lacks `tags` (which would be a plan error):

```hcl
data "resource" all_resource {}
locals {
  all_blocks = flatten([for _, bs in flatten([
    for t, rb in data.resource.all_resource.result : rb]) : [for b in bs : b]])
  tagged   = [for b in local.all_blocks : b.mptf.block_address if try(b.tags, null) != null]
  untagged = [for b in local.all_blocks : b.mptf.block_address if try(b.tags, null) == null]
}

transform "update_in_place" harden_tagged {
  for_each             = try(toset(local.tagged), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
      ignore_changes  = var.ignore_tag_changes ? "[tags]" : "[]"   # emitted as the list [tags]
    }
  }
}

transform "update_in_place" harden_untagged {
  for_each             = try(toset(local.untagged), [])
  target_block_address = each.value
  asstring { lifecycle { prevent_destroy = var.prevent_destroy } }
}
```

To add stronger, resource-aware controls for a specific module (like the
S3-bucket public-access lock), drop a `patches/<framework>/<module>/rules.mptf.hcl`
— it composes automatically, no code change.

## Enabling it

**Docker Compose** (on by default):

```bash
# compose/.env
DYNAMIC_BUILD=true
UPSTREAM_REGISTRY=registry.terraform.io
```

The `registry-api` image is built from `registry-api/Dockerfile`, which bakes in
the patch toolkit (`tofu`, `mapotf`, `hcledit`, `git`, `jq`) plus `scripts/` and
`patches/`, so the API can build in-process (uploads go through the minio-go SDK
— no `mc`).

**Kubernetes / Helm** (off by default — prefer Tekton pre-builds):

```yaml
# values.yaml
registryApi:
  dynamicBuild:
    enabled: true
    upstreamRegistry: registry.terraform.io
```

## Trade-offs

| | Pre-built (Tekton / build.sh) | Dynamic (on demand) |
|---|---|---|
| First request latency | none (already cached) | seconds (fetch + patch) |
| Module coverage | only what you built | **any** upstream module |
| Curation | explicit per module | automatic via `_default` rules |
| Build environment | isolated pipeline | inside the API pod/container |

Notes:

- **Latency / cold start** is paid once per `(module, version, framework)`, then
  cached. Concurrent first-requests are de-duplicated by a per-key lock.
- **`tofu get`** pulls modules only (no providers), so a build does not download
  provider plugins. Module sources are fully qualified to `registry.terraform.io`
  so OpenTofu fetches from the Terraform registry. The fmt/validate step is
  skipped on the hot path (`SKIP_VALIDATE=true`) to keep builds fast.
- **Secret scanning is report-only by default** (`GITLEAKS_STRICT=false`). Real
  upstream modules trip gitleaks on example fixtures, so a hard gate would break
  most dynamic builds. Findings are still logged; set `GITLEAKS_STRICT=true` to
  block (better suited to curated first-party modules).
- **Trust / source allow-list:** by default dynamic mode will fetch and serve
  *any* module name the caller requests (the framework entitlement check still
  applies). Set `ALLOWED_MODULES` (CSV of `<namespace>/<name>` globs, e.g.
  `terraform-aws-modules/*,Azure/avm-res-*`) to restrict which upstream modules
  may be built — a non-matching request fails the build. Empty = allow any.
- **Resource-aware enforcement** for an unknown module is only as strong as the
  `_default` rules until you add a module-specific file. The generic layer
  protects against destruction but cannot, for example, know which attribute on
  an arbitrary resource means "public".
