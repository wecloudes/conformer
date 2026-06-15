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
[`patches/Dockerfile.patch-toolkit`](../patches/Dockerfile.patch-toolkit).

---

## 1. Lifecycle injection

**Goal:** add a `lifecycle` block to a resource you don't own — e.g. protect a
bucket from accidental destruction.

**Tools:** `hcledit` (imperative) or `mapotf` (declarative). This project uses
`mapotf` as the primary engine and `hcledit` as a fallback.

**Declarative (mapotf)** — from
[`patches/cis_v600/s3-bucket/rules.mptf.hcl`](../patches/cis_v600/s3-bucket/rules.mptf.hcl):

```hcl
data "resource" bucket {
  resource_type = "aws_s3_bucket"
}

transform "update_in_place" cis_prevent_destroy {
  for_each             = try(data.resource.bucket.result.aws_s3_bucket, {})
  target_block_address = each.value.mptf.block_address
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
[`patches/cis_v600/s3-bucket/patch.hcl`](../patches/cis_v600/s3-bucket/patch.hcl)
are this layer (documentation-grade opt-out flags).

Stronger: `mapotf` *forces* an attribute regardless of caller input. CIS 3.3
locks all four public-access flags:

```hcl
transform "update_in_place" cis_block_public_access {
  for_each             = try(data.resource.pab.result.aws_s3_bucket_public_access_block, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    block_public_acls       = true
    block_public_policy      = true
    ignore_public_acls       = true
    restrict_public_buckets  = true
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

---

## The toolkit image

Every tool above lives in one image so the pipeline (and any consumer) has a
consistent environment:

```bash
docker build -f patches/Dockerfile.patch-toolkit \
  -t compliance-patch-toolkit:latest patches/
```

Contents (pinned versions, set as `ARG`s in the Dockerfile):

| Tool | Version | License |
|---|---|---|
| OpenTofu | 1.12.2 | MPL-2.0 |
| mapotf | 0.1.4 | MIT |
| graft | 0.2.0 (from source) | MPL-2.0 |
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

## Adding a framework or module

1. Create `patches/<framework>/<module>/rules.mptf.hcl` (structural enforcement)
   and optionally `patch.hcl` (advisory toggles).
2. Add the framework subdomain mapping in
   [`registry-api/main.go`](../registry-api/main.go) (`frameworkMap`) and a
   Keycloak role `framework:<name>`.
3. Add patch + upload tasks for it in
   [`pipeline.yaml`](../charts/conformer/templates/tekton/pipeline.yaml).

The same `rules.mptf.hcl` is reused by Model B with no changes.
