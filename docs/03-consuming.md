# Consuming hardened modules

Practical walkthroughs for both [enforcement models](02-enforcement-models.md),
with Terraform CLI and Terragrunt. Each links to a runnable example.

| | Terraform CLI | Terragrunt |
|---|---|---|
| **Model A** (registry) | [§terraform-a](#terraform--model-a-registry) | [§terragrunt-a](#terragrunt--model-a-tfr) |
| **Model B** (direct) | [§terraform-b](#terraform--model-b-direct-mapotf) | [§terragrunt-b](#terragrunt--model-b-before_hook) |

There is also a third, ungated path for ad-hoc use — point a plain `source` URL
at the registry and ride the version + transformation set on the query string,
no token required: [§Terraform direct go-getter](#terraform--direct-go-getter-mode)
(`/m/`, header redirect) and [§Terragrunt direct go-getter](#terragrunt--direct-go-getter-mode)
(`/dl/`, streamed zip — Terragrunt cannot follow the `/m/` header).

---

## Terraform — Model A (registry)

Source the module from the framework subdomain. `terraform` runs unmodified.

```hcl
# main.tf
module "s3_bucket" {
  source  = "cis.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"

  bucket = "my-compliant-bucket"

  # Supply what the controls require; the plan-gate / check blocks assert these.
  attach_deny_insecure_transport_policy = true
  server_side_encryption_configuration  = { rule = { apply_server_side_encryption_by_default = { sse_algorithm = "aws:kms" } } }
  versioning = { enabled = true }
}
```

```bash
terraform login cis.conformer.local   # browser → Keycloak → credentials.tfrc.json
terraform init                          # pulls the CIS-hardened zip
terraform plan
```

**Switch framework** = change the subdomain (`iso27001.` / `soc2.`). The
registry serves a different hardened variant of the same module + version.

---

## Terraform — Model B (direct mapotf)

No registry. Patch the upstream module locally at plan time.

Runnable example: **[`examples/consumer-side-mapotf/`](../examples/consumer-side-mapotf/)**

```bash
cd examples/consumer-side-mapotf
./harden.sh cis_v600 5.11.0
```

What `harden.sh` does:

1. clones `terraform-aws-s3-bucket` v5.11.0 into `./upstream` (transient, not a fork)
2. applies the CIS framework's **transformation units** to it in place — one
   `mapotf transform` per unit, e.g.
   `mapotf transform -r --mptf-dir <repo>/transformations/aws-s3-public-access/s3-bucket`,
   then `.../aws-s3-checks-cis/s3-bucket`, plus the generics
   `.../tags/_default`, `.../destroy/_default`, `.../aws-secure-defaults/_default`
3. `terraform plan -out tfplan`
4. `scripts/plan-gate.sh tfplan <framework>` — jq assertions (S3 + edge/transit:
   ELB TLS, WAF association, API Gateway logging); non-zero exit fails CI
5. `mapotf reset` — restores `./upstream`

Model B now selects **units**, not a monolithic per-framework patch dir. A
framework (`frameworks/<framework>.hcl`) is just a named list of units; applying
"the CIS framework" to a module means applying that framework's units in order.
Units with no rules for the module are skipped.

`main.tf` there is intentionally non-compliant so you see the gate fire; fix the
inputs to go green.

---

## Terragrunt — Model A (`tfr://`)

Terragrunt speaks the registry protocol natively via the `tfr://` source.

Runnable example: **[`examples/terragrunt/model-a-registry/`](../examples/terragrunt/model-a-registry/)**

```hcl
# root.hcl — framework set once, inherited by every unit
locals { framework_host = "cis.conformer.local" }

# s3-bucket/terragrunt.hcl
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}
terraform {
  source = "tfr://${include.root.locals.framework_host}/terraform-aws-modules/s3-bucket/aws?version=5.11.0"
}
```

```bash
cd examples/terragrunt/model-a-registry/s3-bucket
terraform login cis.conformer.local        # or: export TG_TF_REGISTRY_TOKEN=<token>
terragrunt plan
```

> **Terragrunt ≥ 1.0.5 required** when the provider cache (`TG_PROVIDER_CACHE`)
> is enabled. Older versions forward the cache key instead of your registry
> token and the registry returns `403 Forbidden`.

---

## Terragrunt — Model B (`before_hook`)

No registry. A `before_hook` runs `mapotf` against the module Terragrunt
downloads into `.terragrunt-cache/`, before each plan/apply. The hook applies the
framework's **transformation units** — here the two s3-bucket-bound units of the
CIS framework — instead of a single per-framework patch dir.

Runnable example: **[`examples/terragrunt/model-b-mapotf/`](../examples/terragrunt/model-b-mapotf/)**

```hcl
# root.hcl — hook lives here, so every unit inherits it and cannot opt out
terraform {
  before_hook "compliance_public_access" {
    commands = ["plan", "apply", "destroy"]
    execute  = ["mapotf", "transform", "-r", "--mptf-dir",
                "${local.repo_root}/transformations/aws-s3-public-access/s3-bucket"]
  }
  before_hook "compliance_s3_checks" {
    commands = ["plan", "apply", "destroy"]
    execute  = ["mapotf", "transform", "-r", "--mptf-dir",
                "${local.repo_root}/transformations/aws-s3-checks-cis/s3-bucket"]
  }
  extra_arguments "save_plan" {
    commands  = ["plan"]
    arguments = ["-out=tfplan"]
  }
  after_hook "plan_gate" {
    commands     = ["plan"]
    execute      = ["${local.repo_root}/scripts/plan-gate.sh", "tfplan"]
    run_on_error = false
  }
}

# s3-bucket/terragrunt.hcl — real upstream source, deep-merged with root's hooks
include "root" {
  path           = find_in_parent_folders("root.hcl")
  merge_strategy = "deep"
}
terraform {
  source = "git::https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git//.?ref=v5.11.0"
}
```

```bash
cd examples/terragrunt/model-b-mapotf/s3-bucket
terragrunt plan          # before_hook patches, plan runs, after_hook gates
```

Run `terragrunt run-all plan` from the root in CI to enforce across **all**
units — a unit cannot skip the hook because it is defined in `root.hcl`.

---

## Terraform — direct go-getter mode

An ad-hoc, **ungated** path: no framework subdomain, no token, no entitlement.
Point a plain Terraform `source` at the registry apex over a go-getter HTTP URL
and ride both the version *and* the transformation set on the query string. The
server resolves `?transformation=`, builds exactly those units (in order),
caches the result under a canonical profile key, and returns the patched zip via
`X-Terraform-Get`.

Runnable example: **[`examples/direct-transform/`](../examples/direct-transform/)**

```hcl
# main.tf
module "automation" {
  # go-getter http source — a full https:// URL, NOT a registry source.
  # No `version =` argument: version is a query param, and the transformation
  # set rides alongside it.
  source = "https://conformer.local/m/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0&transformation=tags,destroy"

  name                = "smoke-aa"
  resource_group_name = "rg-smoke"
  location            = "westeurope"
  sku                 = "Basic"
}
```

```bash
cd examples/direct-transform
terraform init        # downloads the patched module from the direct endpoint — no `terraform login`
grep -rn ignore_changes .terraform/modules/   # proof the transforms landed
```

Notes:

- The source is the registry **apex** (`conformer.local/m/<ns>/<name>/<provider>`),
  not a `cis.`/`iso27001.`/`soc2.` framework subdomain.
- Because it is a go-getter HTTP source rather than the registry protocol, there
  is **no separate `version =` argument** — `?version=` carries it.
- `?transformation=tags,destroy` selects the transformation **units** directly;
  the server builds only those, in that order. Swap in any unit name(s).
- `?framework=cis` selects a whole framework bundle, and you can combine the two
  — `?framework=cis&transformation=tags,destroy` expands the framework's units
  and applies the ad-hoc units on top. Pass either or both (at least one).

  ```hcl
  source = "https://conformer.local/m/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0&framework=cis&transformation=tags,destroy"
  ```

- This path is **open** — no Keycloak login, no `credentials.tfrc.json`, no
  registry token, even with `?framework=`. Composing more units can only harden,
  never weaken, so there is nothing to gate; the entitlement check (which tenant
  may use which framework) lives only on the gated framework subdomains (Model A).
  Cache keys: `set.<units>` (units only), `<framework>` (framework only — shared
  with the subdomain path), `<framework>.plus.<units>` (combined).

---

## Terragrunt — direct go-getter mode (`/dl/`)

Terragrunt's `source` is plain go-getter, which fetches archives but does **not**
follow the `X-Terraform-Get` header that `/m/` returns (only Terraform's module
installer does). So Terragrunt uses the **`/dl/`** endpoint, which streams the
zip *body* instead. Same ad-hoc selection, same cache, same open model — version
rides the **path** (`.../<version>.zip`), and `archive=zip` forces go-getter to
treat the response as a zip despite the trailing query string.

```hcl
# terragrunt.hcl — ad-hoc tags-only on an upstream Azure module, no token.
terraform {
  source = "https://conformer.local/dl/Azure/avm-res-storage-storageaccount/azurerm/0.6.4.zip?archive=zip&transformation=tags"
}
```

```bash
rm -rf .terragrunt-cache    # source URL changed → force a refetch
terragrunt init
terragrunt plan             # applying ignore_changes=[tags] to an existing
                            # resource is metadata only → expect 0 to add/change/destroy
```

Compose units the same way as `/m/`: `?archive=zip&transformation=tags,destroy`
or `?archive=zip&framework=cis&transformation=tags`. Append `//.` before the `?`
if Terragrunt asks for a subdir.

**Named alternative — `tfr://` + a framework.** When the unit set is a standing
policy you reuse across modules (not a one-off), make it a framework — a named
bundle in `frameworks/<name>.hcl`. For example [`frameworks/tags.hcl`](../frameworks/tags.hcl)
is the single `tags` unit, served (gated) on the `tags.` subdomain:

```hcl
# terragrunt.hcl — same module + transform via the registry protocol (gated)
terraform {
  source = "tfr://tags.conformer.local/Azure/avm-res-storage-storageaccount/azurerm?version=0.6.4"
}
```

```bash
export TG_TF_REGISTRY_TOKEN=<token entitled to the "tags" framework>
terragrunt init && terragrunt plan
```

Pick `/dl/` for ungated one-offs; pick `tfr://<framework>` when you want a named,
entitlement-gated, reusable set. Both produce the identical patched module — the
example above was verified end-to-end against `Azure/avm-res-storage-storageaccount/azurerm`
`0.6.4` (4 `ignore_changes = [tags]` injected, addresses unchanged, clean plan).

---

## CI integration

For Model B in CI, `mapotf` / `terraform` / `jq` must be on PATH. The patch
toolkit ships inside the prebuilt multi-arch image
[`wecloudes/conformer`](https://hub.docker.com/r/wecloudes/conformer) (it bundles
all the transform tooling), so reuse it as your CI container:

```yaml
# GitHub Actions
jobs:
  plan:
    runs-on: ubuntu-latest
    container: wecloudes/conformer:latest
    steps:
      - uses: actions/checkout@v4
      - run: terragrunt run-all plan --terragrunt-non-interactive
        working-directory: examples/terragrunt/model-b-mapotf
```

```yaml
# GitLab CI
compliance-plan:
  image: wecloudes/conformer:latest
  script:
    - cd examples/terragrunt/model-b-mapotf
    - terragrunt run-all plan --terragrunt-non-interactive
```

If you'd rather not run inside that image, drive the transforms directly from
the repo scripts — `scripts/apply-transforms.sh` to patch the module and
`scripts/plan-gate.sh tfplan` to gate the plan — provided `mapotf` /
`terraform` / `jq` are installed on the runner.

For Model A, no special image is needed — only `terraform`/`terragrunt` plus the
registry token (`TG_TF_REGISTRY_TOKEN` or a mounted `credentials.tfrc.json`).
The hardened modules are served by the Docker Compose stack: bring it up from
`compose/` (`docker compose up`), or pre-build the framework variants ahead of
time with `compose/build.sh`.
