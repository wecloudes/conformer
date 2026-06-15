# Conformer — Documentation

How Conformer hardens Terraform/OpenTofu modules, the strategies for delivering
that hardening, and how to consume it. Tooling licenses: see
[LICENSES.md](../LICENSES.md).

Read in order:

1. **[Transformation techniques](01-transformation-techniques.md)** — *how* a
   module is hardened. The five-layer pipeline (sanitize → strip → transform →
   toggle → gate), the tools behind each layer (`sed`, `awk`, `mapotf`,
   `hcledit`, `gitleaks`, `jq`), and before/after HCL for each.

2. **[Enforcement models](02-enforcement-models.md)** — *where* the
   transformation runs and *how strongly* it is enforced. Model A (registry,
   server-gated) vs Model B (direct, opt-in), the enforcement spectrum, the
   decision matrix, and what each model does **not** protect against.

3. **[Consuming hardened modules](03-consuming.md)** — *how to use it*, with
   runnable walkthroughs for Terraform CLI and Terragrunt against both models,
   each linked to a scaffolded example.

4. **[Dynamic patching](04-dynamic-patching.md)** — serve *any* upstream module,
   patched on demand for the subdomain's framework, with no pre-build. Generic
   `_default` units + on-the-fly fetch/patch/cache.

5. **[Transformation catalog](05-transformation-catalog.md)** — a cookbook of
   real transformations (encryption, public-access, TLS, logging, tags,
   removal, assertions) mapped to controls and provider resources. **Start here
   if you're authoring rules.**

## Background

The transformation techniques come from a "DIY playbook" — given an upstream
Terraform module, how do you bend it to a compliance framework without owning
the upstream source? Four techniques plus the registry pattern:

Mechanically, those techniques are packaged as **atomic, composable
transformation units** under [`transformations/`](../transformations/) (a
`_default/` rule applies to any module; a `<module>/` rule is module-specific).
A **framework** is just a *named bundle* of units, declared in
[`frameworks/<framework>.hcl`](../frameworks/) — so `cis_v600` is a manifest
listing the units it enables, not a folder of rules.

| Technique | Tooling | Documented in |
|---|---|---|
| Lifecycle injection | `hcledit` / `mapotf` | [techniques §1](01-transformation-techniques.md#1-lifecycle-injection) |
| Block removal | `awk` | [techniques §2](01-transformation-techniques.md#2-block-removal) |
| Attribute restriction | `validation {}` + `jq` | [techniques §3](01-transformation-techniques.md#3-attribute-restriction) |
| Content sanitization | `sed` + `gitleaks` | [techniques §4](01-transformation-techniques.md#4-content-sanitization) |
| Roll-your-own registry | this project | [enforcement §model-a](02-enforcement-models.md#model-a--registry-server-gated) |

## Deploying the registry (Model A)

| Path | When |
|---|---|
| [`compose/`](../compose/) | **Simple** — single host, Docker Compose, static-token auth, no Keycloak/Tekton |
| [`charts/conformer/`](../charts/conformer/) | **Production** — Kubernetes/Helm, Keycloak OIDC, Tekton build pipeline |

Both serve the identical Registry Protocol and run the same hardening pipeline;
Compose swaps Tekton for a one-shot builder and Keycloak for static tokens.

## Consuming

Two ways to pull a hardened module from a running registry:

| Mode | Source | Trait |
|---|---|---|
| **Framework subdomain** (registry protocol, gated) | `source = "cis.conformer.local/<ns>/<name>/<provider>"` + a separate `version = "x"` | Entitlement-checked; the `cis`/`iso27001`/`soc2` subdomain selects the framework bundle. |
| **Direct go-getter** (ad-hoc, open) | `source = "https://conformer.local/m/<ns>/<name>/<provider>?version=X&transformation=tags,destroy"` (no `version =` arg) | A go-getter HTTP source — *not* the registry protocol; ungated, so a convenience rather than a control. See [`examples/direct-transform/`](../examples/direct-transform/). |

## Examples

| Path | Shows |
|---|---|
| [`examples/direct-transform/`](../examples/direct-transform/) | Direct go-getter consumption — ad-hoc transformation set on an `https://` source query string (`?version=…&transformation=tags,destroy`), ungated, no `version =` arg |
| [`examples/consumer-side-mapotf/`](../examples/consumer-side-mapotf/) | Model B with plain Terraform — patch upstream locally, no registry |
| [`examples/terragrunt/model-a-registry/`](../examples/terragrunt/model-a-registry/) | Model A with Terragrunt — `tfr://` registry source |
| [`examples/terragrunt/model-b-mapotf/`](../examples/terragrunt/model-b-mapotf/) | Model B with Terragrunt — `before_hook` mapotf |
