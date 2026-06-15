# Transformation techniques

Compliance hardening here is **real structural HCL rewriting**, not appended
documentation. A module is transformed through five layers. Each layer is one
technique from the DIY playbook, and each maps to concrete files in the repo.

```
upstream module (fetched at a git tag)
        │
   ┌────▼─────────────────────────────────────────────┐
   │ Layer 1  SANITIZE     sed + gitleaks              │  strip IDs/regions, fail on secrets
   │ Layer 2  STRIP        awk                         │  remove provisioner / local-exec
   │ Layer 3  TRANSFORM    mapotf + hcledit            │  inject lifecycle, override attrs, add checks
   │ Layer 4  TOGGLES      variable { validation }     │  source-time opt-out flags
   │ Layer 5  GATE         terraform show -json + jq   │  plan-time assertions (consumer/CI)
   └────┬─────────────────────────────────────────────┘
        ▼
   hardened module → zip → registry  (Model A)
   hardened module in cache → plan    (Model B)
```

Layers 1–4 run wherever the transform happens (Tekton for Model A, the consumer
machine for Model B). Layer 5 runs against a real plan, so it lives on the
consumer/CI side in both models.

The build orchestration is
[`charts/conformer/templates/tekton/task-patch-module.yaml`](../charts/conformer/templates/tekton/task-patch-module.yaml).
All tools ship in one image,
[`toolkit/Dockerfile.patch-toolkit`](../toolkit/Dockerfile.patch-toolkit).

---

## 1. Lifecycle injection

**Goal:** add a `lifecycle` block to a resource you don't own — e.g. protect a
bucket from accidental destruction.

**Tools:** `hcledit` (imperative) or `mapotf` (declarative). This project uses
`mapotf` as the primary engine and `hcledit` as a fallback.

**Declarative (mapotf)** — from the generic `destroy` unit,
[`transformations/destroy/_default/rules.mptf.hcl`](../transformations/destroy/_default/rules.mptf.hcl).
Because `prevent_destroy` is a meta-argument valid on *any* resource type, this
unit is generic (it ships under `_default`, not under a module dir) and hits
every managed resource:

```hcl
data "resource" all_resource {
}

locals {
  all_resource_blocks = flatten([
    for resource_type, resource_blocks in data.resource.all_resource.result : resource_blocks
  ])
  all_blocks = flatten([for _, blocks in local.all_resource_blocks : [for b in blocks : b]])
  all_addrs  = [for b in local.all_blocks : b.mptf.block_address]
}

transform "update_in_place" prevent_destroy {
  for_each             = try(toset(local.all_addrs), [])
  target_block_address = each.value
  asstring {
    lifecycle {
      prevent_destroy = var.prevent_destroy
    }
  }
}
```

**Imperative (hcledit)** — same effect, one command:

```bash
hcledit attribute append \
  'resource.aws_s3_bucket.this.lifecycle.prevent_destroy' true -f main.tf -u
```

**Before → after:**

```hcl
resource "aws_s3_bucket" "this" {        resource "aws_s3_bucket" "this" {
  bucket = var.bucket             ──►      bucket = var.bucket
}                                          lifecycle {
                                             prevent_destroy = true
                                           }
                                         }
```

`mapotf` addresses blocks by label (`aws_s3_bucket.this`), so it works even when
the resource uses `count`/`for_each`. Prefer it when you need to hit *every*
resource of a type; reach for `hcledit` for a single targeted edit.

`destroy` is one of two **generic** transformation units (the other is `tags`).
They are separate units, but when both are selected `mapotf`'s
`update_in_place` merges their lifecycle settings into a *single* `lifecycle`
block — so the units compose without producing a duplicate block.

---

## 2. Block removal

**Goal:** delete an entire nested block the upstream shipped — most importantly
`provisioner` / `local-exec`, which run arbitrary commands and often carry
secrets.

**Tool:** `awk` brace-counter (works on any HCL, no schema needed).

From the patch task:

```bash
awk '
  /^[[:space:]]*provisioner / { s=1; d=0 }
  s { if (/{/) d++;
      if (/}/ && d>0) { d--; if (d==0) { s=0; next } }
      next }
  { print }
' main.tf > main.stripped && mv main.stripped main.tf
```

The counter tracks brace depth so nested `{ }` inside the block don't end it
early. **Before → after:**

```hcl
resource "null_resource" "boot" {        resource "null_resource" "boot" {
  triggers = { host = var.host }   ──►      triggers = { host = var.host }
  provisioner "local-exec" {              }
    command = "./install.sh"
  }
}
```

`mapotf` can also remove blocks (`remove_block`, `remove_block_element`), but
`awk` is kept here because it is schema-agnostic and matches the playbook.

---

## 3. Attribute restriction

**Goal:** stop a caller from setting a value that breaks compliance (e.g. an
instance type outside an approved list, or public access left open). Two layers,
because some values are known at source-time and others only at plan-time.

### Layer 1 — source-time (`validation {}` and forced attributes)

A `variable` with a `validation` block rejects bad input before plan. The
advisory toggles in
[`transformations/aws-s3-checks-cis/s3-bucket/patch.hcl`](../transformations/aws-s3-checks-cis/s3-bucket/patch.hcl)
are this layer (documentation-grade opt-out flags).

Stronger: `mapotf` *forces* an attribute regardless of caller input. The
`aws-s3-public-access` unit
([`transformations/aws-s3-public-access/s3-bucket/rules.mptf.hcl`](../transformations/aws-s3-public-access/s3-bucket/rules.mptf.hcl))
locks all four public-access flags (CIS 3.3 / ISO A.8.3 / SOC2 CC6.1 require
this identically, so it lives in one framework-agnostic unit):

```hcl
transform "update_in_place" block_public_access {
  for_each             = try(data.resource.pab.result.aws_s3_bucket_public_access_block, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
}
```

### Layer 2 — plan-time (`check {}` and `jq`)

Some controls depend on values that resolve only at plan time. mapotf injects a
`check` block (surfaces a warning), and
[`scripts/plan-gate.sh`](../scripts/plan-gate.sh) makes it a hard CI failure:

```bash
terraform show -json tfplan | jq -e '
  [ .resource_changes[]
    | select(.type=="aws_s3_bucket_public_access_block")
    | select(.change.after.block_public_acls != true) ] | length == 0'
# exits non-zero on a violation → CI red
```

Use Layer 1 to reject obviously-bad config early; use Layer 2 to assert the
*actual planned resources* are compliant once all expressions resolve.

---

## 4. Content sanitization

**Goal:** strip hardcoded account IDs, regions, and secrets the upstream may
have baked into examples or defaults.

**Tools:** `sed` (rewrite identifiers) + `gitleaks` (fail on anything that still
looks like a secret).

From the patch task:

```bash
# 12-digit AWS account IDs → caller's own identity
find . -name '*.tf' -print0 | xargs -0 -r sed -i -E \
  's/[0-9]{12}/${data.aws_caller_identity.current.account_id}/g'

# hardcoded region in ARNs → caller's region
find . -name '*.tf' -print0 | xargs -0 -r sed -i -E \
  's/(arn:aws:[a-z0-9-]*:)(us|eu|ap|sa|ca|me|af)-[a-z]+-[0-9]/\1${data.aws_region.current.name}/g'

# fail the build if any secret remains
gitleaks detect --no-git --source . --redact --exit-code 1
```

**Before → after:**

```hcl
Principal = {                            Principal = {
  AWS = "arn:aws:iam::123456789012:root"   AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}                              ──►        }
```

**AWS-gated.** The account-id / region rewrite only makes sense for modules that
use the AWS provider — the rewritten references point at
`data.aws_caller_identity.current` and `data.aws_region.current`, which a
non-AWS (e.g. Azure) module has no provider for. The
[`aws-secure-defaults`](../transformations/aws-secure-defaults/_default/aws-datasources.mptf.hcl)
unit therefore *gates* the rewrite: it injects those data sources (and so opts a
module into the rewrite) **only** when the module actually declares `aws_*`
resources, and only when they aren't already declared. A pure-Azure module is
left untouched — no dangling references, no spurious AWS provider dependency.

---

## The toolkit image

Every tool above lives in one image so the pipeline (and any consumer) has a
consistent environment:

```bash
docker build -f toolkit/Dockerfile.patch-toolkit \
  -t compliance-patch-toolkit:latest toolkit/
```

Contents (pinned versions, set as `ARG`s in the Dockerfile):

| Tool | Version | License |
|---|---|---|
| OpenTofu | 1.12.2 | MPL-2.0 |
| mapotf | 0.1.4 | MIT |
| hcledit | 0.2.17 | MIT |
| gitleaks | 8.30.1 | MIT |

plus `jq`/`gawk`/`sed`. OpenTofu replaces Terraform (BUSL); uploads use the
minio-go SDK, not the AGPL `mc`. See [LICENSES.md](../LICENSES.md). Set it as
`tekton.patchImage` in
[`values.yaml`](../charts/conformer/values.yaml), and use the same
image in CI for Model B (see
[consuming §CI](03-consuming.md#ci-integration)).

**Architecture:** the Dockerfiles declare `ARG TARGETARCH` with no default, so
BuildKit fills in the build platform (`amd64` / `arm64`) and the right native
binaries are downloaded. Do not hardcode `amd64` — emulated Go binaries crash
under QEMU (`fatal error: lfstack.push`) on Apple Silicon.

**gitleaks gate:** the sanitize step reports findings but only fails the build
when `GITLEAKS_STRICT=true`. Third-party modules routinely trip the scanner on
example fixtures (`examples/*.pfx`, sample passwords), so the default is
report-only; enable strict mode for curated first-party modules.

## Adding a transformation unit or framework

Rules are organized as **atomic, composable transformation units** under
[`transformations/`](../transformations/), and a **framework** is a named
*bundle* of those units declared in [`frameworks/`](../frameworks/). To extend
the catalog:

1. **Add a unit.** Create `transformations/<unit>/_default/rules.mptf.hcl` for a
   generic rule that applies to any module, or
   `transformations/<unit>/<module>/rules.mptf.hcl` for a module-specific rule
   (the `<module>/` path mirrors the upstream module's directory layout, e.g.
   `<unit>/rds/modules/db_instance/`). Add a sibling `patch.hcl` for advisory
   toggles where useful.
2. **Add or extend a framework** by editing/creating `frameworks/<framework>.hcl`
   — a manifest with `description = "..."` and
   `transformations = ["unit-a", "unit-b", ...]`. The build engine
   [`scripts/patch-module.sh`](../scripts/patch-module.sh) expands the manifest
   and applies each listed unit; units with no rules for the module being built
   are simply skipped. (The same script also accepts `TRANSFORMATIONS=a,b`
   directly for ad-hoc sets — the units are identical either way.)
3. For a new registry **subdomain**, add the framework mapping in
   [`registry-api/main.go`](../registry-api/main.go) (`frameworkMap`, e.g.
   `cis → cis_v600`) and a Keycloak role `framework:<name>`, then wire patch +
   upload tasks in
   [`pipeline.yaml`](../charts/conformer/templates/tekton/pipeline.yaml).

The same units are reused by Model B with no changes.
