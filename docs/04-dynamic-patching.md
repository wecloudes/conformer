# Dynamic (on-demand) patching

By default the registry serves modules that were patched ahead of time (the
compose `builder` / `compose/build.sh`). **Dynamic patching** removes that step:
request *any*
module through the registry and it is fetched from the upstream Terraform
registry, patched, cached, and served — the first time it is asked for.

Dynamic build backs **both** consumption modes:

- the **framework subdomain** path (registry protocol, token-gated) —
  `cis.conformer.local/<ns>/<name>/<provider>` resolves to a framework manifest;
- the **direct go-getter** path (ad-hoc, open) —
  `https://conformer.local/m/<ns>/<name>/<provider>?version=&transformation=`
  builds an ad-hoc transformation set on demand and caches it under a canonical
  key.

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
3. expands the framework manifest (`frameworks/cis_v600.hcl`) to its
   transformation units, applies them, and serves the hardened zip — no
   pre-build, no per-module entry required for that specific module

## How it works

```
terraform init
   │  GET …/versions          ─► API proxies registry.terraform.io versions
   │                              (so any version is resolvable)
   │  GET …/{version}/download
   ▼
API handleDownload  (framework subdomain)   handleDirectModule  (/m/ go-getter)
   ├─ object in MinIO?  ── yes ─► presigned URL (X-Terraform-Get)
   └─ no  ─► ensureBuilt()
              ├─ lock per object key (dedupe concurrent requests)
              ├─ scripts/build-dynamic.sh ns name provider version framework
              │     • tofu get             → pull module (modules only, no providers)
              │     • scripts/patch-module.sh → framework manifest expands to
              │       transformation units (generic + module-specific layers);
              │       direct mode passes TRANSFORMATIONS=a,b instead
              │     • (API uploads the zip via the minio-go SDK)
              └─ presigned URL  → {…}/{framework|set.<units>}/{version}.zip
```

The framework subdomain path keys the cache by
`{ns}/{name}/{provider}/{framework}/{version}.zip`; the direct path keys it by
`{ns}/{name}/{provider}/set.<units>/{version}.zip`, where `<units>` is the
**sorted, deduped** transformation list (so `tags,destroy` and `destroy,tags`
share one cache entry). Subsequent requests for the same key hit the MinIO cache
directly. Implementation: `registry-api/build.go` (`ensureBuilt`,
`fetchUpstreamVersions`), `registry-api/main.go` (`handleDownload`,
`handleDirectModule`), and `scripts/build-dynamic.sh`.

## Generic vs module-specific rules

Dynamic patching works on modules that have **no** dedicated bindings because
generic hardening comes from **generic transformation units** — atomic,
framework-agnostic units whose `_default/` rules apply to *any* module:

```
transformations/<unit>/_default/rules.mptf.hcl   # applied to ANY module
transformations/<unit>/<module>/rules.mptf.hcl   # layered on top when present
```

A **framework** is a manifest (`frameworks/<framework>.hcl`) that names a flat
list of units, e.g. `transformations = ["destroy", "tags", ...]`.
`scripts/patch-module.sh` expands the manifest and applies each unit's
`_default` rules first, then its module-specific rules if they exist. Units that
have no rules for the module being built are simply skipped. The generic units
that harden an arbitrary on-demand module are:

- **`destroy`** — `prevent_destroy` on every managed resource (a lifecycle
  meta-argument valid on all resource types).
- **`tags`** — `ignore_changes = [tags]` on every resource that *has* a `tags`
  attribute, so tag drift (tags applied out-of-band by org automation / Azure
  Policy) does not force diffs.
- **`avm-secure-defaults`** / **`aws-secure-defaults`** — provider-family secure
  baselines layered on top.

`tags` only targets resources that have a `tags` attribute, so `ignore_changes`
is never added to a resource that lacks `tags` (which would be a plan error).
`destroy` and `tags` compose: mapotf's `update_in_place` merges both settings
into a single `lifecycle` block per resource (no duplicate block):

```hcl
# transformations/tags/_default/rules.mptf.hcl
data "resource" all_resource {}
locals {
  all_resource_blocks = flatten([
    for resource_type, resource_blocks in data.resource.all_resource.result : resource_blocks
  ])
  all_blocks = flatten([for _, blocks in local.all_resource_blocks : [for b in blocks : b]])
  tagged     = [for b in local.all_blocks : b.mptf.block_address if try(b.tags, null) != null]
}

transform "update_in_place" ignore_tag_changes {
  for_each             = try(toset(local.tagged), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      ignore_changes = var.ignore_tag_changes ? "[tags]" : "[]"   # emitted as the list [tags]
    }
  }
}
```

To add stronger, resource-aware controls for a specific module (like the
S3-bucket public-access lock in `aws-s3-public-access`), drop a
`transformations/<unit>/<module>/rules.mptf.hcl` and list the unit in the
framework manifest — it composes automatically, no code change.

## Enabling it

**Docker Compose** (on by default):

```bash
# compose/.env
DYNAMIC_BUILD=true
UPSTREAM_REGISTRY=registry.terraform.io
DIRECT_MODE=true              # serve the /m/ go-getter direct path (default)
```

The `registry-api` image is built from `registry-api/Dockerfile`, which bakes in
the patch toolkit (`tofu`, `mapotf`, `hcledit`, `git`, `jq`, `gitleaks`, plus
`sed`/`awk`) along with `scripts/`, `transformations/`, and `frameworks/`, so the
API can build in-process (uploads go through the minio-go SDK — no `mc`).

## Direct go-getter path (ad-hoc transformation sets)

Dynamic build also serves a second, framework-less endpoint. Instead of a
registry source resolved through a gated framework subdomain, the consumer
writes a plain go-getter HTTP source and names the transformation units in the
query string:

```hcl
module "automation" {
  # go-getter http source: version + transformation set in the query string.
  # NOTE: no `version =` argument here — that is registry-only; the version
  # rides the query string, and there is no token / entitlement check.
  source = "https://conformer.local/m/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0&transformation=tags,destroy"
}
```

`handleDirectModule` sanitizes and **sorts/dedupes** the `transformation` list,
builds the module with exactly those units (`TRANSFORMATIONS=tags,destroy`, no
framework), and caches it under the canonical key
`{ns}/{name}/{provider}/set.destroy-tags/{version}.zip`. Ad-hoc sets are never
pre-baked, so this path always builds on a miss regardless of `DYNAMIC_BUILD`;
it is gated only by `DIRECT_MODE` (on by default). A worked example lives in
`examples/direct-transform/`.

## Trade-offs

| | Pre-built (builder / build.sh) | Dynamic (on demand) |
|---|---|---|
| First request latency | none (already cached) | seconds (fetch + patch) |
| Module coverage | only what you built | **any** upstream module |
| Curation | explicit per module | automatic via generic transformation units |
| Build environment | isolated pipeline | inside the API container |

Notes:

- **Latency / cold start** is paid once per cache key — `(module, version,
  framework)` on the subdomain path, or `(module, version, sorted-unit-set)` on
  the direct path — then cached. Concurrent first-requests are de-duplicated by a
  per-key lock.
- **`tofu get`** pulls modules only (no providers), so a build does not download
  provider plugins. Module sources are fully qualified to `registry.terraform.io`
  so OpenTofu fetches from the Terraform registry. The fmt/validate step is
  skipped on the hot path (`SKIP_VALIDATE=true`) to keep builds fast.
- **AWS account-id / region sanitization** (rewriting hardcoded 12-digit account
  ids and `arn:aws:...:<region>` to `data.aws_caller_identity` /
  `data.aws_region`) runs **only** on modules that actually use the AWS provider;
  it is skipped on non-AWS modules so it cannot inject an `aws_*` data source or
  corrupt 12-digit runs (e.g. Azure GUIDs).
- **Secret scanning is report-only by default** (`GITLEAKS_STRICT=false`). Real
  upstream modules trip gitleaks on example fixtures, so a hard gate would break
  most dynamic builds. Findings are still logged; set `GITLEAKS_STRICT=true` to
  block (better suited to curated first-party modules).
- **Trust / source allow-list:** by default dynamic mode will fetch and serve
  *any* module name the caller requests. On the framework subdomain path the
  token entitlement check still applies; the direct `/m/` path is open by design
  (no token, no entitlement). `ALLOWED_MODULES` (CSV of `<namespace>/<name>`
  globs, e.g. `terraform-aws-modules/*,Azure/avm-res-*`) is the build-time guard
  for both: it restricts which upstream modules may be built — a non-matching
  request fails the build. Empty = allow any.
- **Resource-aware enforcement** for an unknown module is only as strong as the
  generic units' `_default` rules until you add module-specific rules to a unit.
  The generic layer protects against destruction but cannot, for example, know
  which attribute on an arbitrary resource means "public".
