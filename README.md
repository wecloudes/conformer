# Conformer

**Conform any Terraform module to a compliance framework — without forking it.**

Conformer is a framework-aware Terraform/OpenTofu module registry that transforms
upstream modules to a compliance framework (CIS, ISO 27001, SOC 2, …) on the fly.
Compliance content is decomposed into atomic, composable **transformation units**;
a **framework** is just a named bundle of those units. Point Terraform at a
framework subdomain and Conformer fetches the upstream module, expands the
framework to its unit list, applies them, and serves the hardened result — either
pre-built or patched on demand. The same hardened module is also reachable
ad-hoc via a direct go-getter URL that names the units inline. Inspired by
[compliance.tf](https://compliance.tf), built entirely on open-source components
(permissive / weak-copyleft only — see [LICENSES.md](LICENSES.md)).

> **New here?** Start with [`docs/`](docs/): how modules are hardened
> ([transformation techniques](docs/01-transformation-techniques.md)), the
> delivery strategies ([enforcement models](docs/02-enforcement-models.md)), how
> to consume them ([consuming guide](docs/03-consuming.md)), and how the registry
> patches *any* upstream module on demand
> ([dynamic patching](docs/04-dynamic-patching.md)).

## Architecture

Conformer ships as a single-host Docker Compose stack:

```
*.conformer.local + apex (wildcard DNS → 127.0.0.1)
        │
  ┌─────▼──────┐
  │   Caddy    │  wildcard reverse proxy + automatic local TLS
  └─────┬──────┘
        │
  ┌─────▼───────┐        ┌──────────┐
  │ Registry    │───────▶│  MinIO   │  S3-compatible zip storage
  │ API (Go)    │        └──────────┘
  │ + toolkit   │
  └─────┬───────┘
        │ on-demand dynamic build
        ▼  (fetch upstream → patch → cache)
  ┌─────────────┐
  │  builder    │  one-shot pre-builder (./build.sh), same image
  └─────────────┘
```

Auth defaults to static bearer tokens. OIDC is still supported in code
(`AUTH_MODE=keycloak`) but only against an **external** Keycloak you run
yourself — there is no bundled identity provider.

### Components

The whole product is the four Compose services in [`compose/`](compose/):

| Service | Tool | Purpose |
|---|---|---|
| `registry-api` | Custom Go service (bundled toolkit) | Terraform Module Registry Protocol v1 + `/m/` direct endpoint; builds modules on demand |
| `versitygw` | Versity S3 Gateway (Apache-2.0) | S3 storage for module zips (POSIX backend) |
| `builder` | one-shot `./build.sh` (registry-api image) | Pre-build / warm the cache, upload to S3 |
| `caddy` | Caddy | Wildcard subdomain routing + automatic local TLS |

The patch toolkit (tofu/mapotf/hcledit/jq/gitleaks) is bundled **inside** the
`registry-api` image — there is no separate toolkit image.

### How it works

1. Framework subdomains (`cis.conformer.local`, `iso27001.conformer.local`) all resolve to the same Caddy proxy
2. The Registry API extracts the framework from the `Host` header
3. Validates the Bearer token (static tokens by default; an external Keycloak JWKS when `AUTH_MODE=keycloak`), checks framework entitlement
4. Expands the framework manifest to its transformation-unit list, builds (or reuses) the hardened zip
5. Returns a presigned MinIO URL and Terraform downloads / uses the patched module transparently

## Module transformation

Compliance hardening is real structural HCL rewriting, not just appended
documentation. The build applies the DIY transformation playbook in layers:

| Layer | Tool | What it does |
|---|---|---|
| Sanitization | `sed` + `gitleaks` | strip hardcoded account IDs / regions (AWS-provider modules only), fail on leaked secrets |
| Block removal | `awk` brace-counter | strip injected `provisioner` / `local-exec` blocks |
| Structural | `mapotf` + `hcledit` | inject `lifecycle { prevent_destroy }`, override insecure attributes (e.g. force public-access flags shut), add plan-time `check` blocks |
| Advisory toggles | `variable { validation }` | source-time opt-out flags per control |
| Plan-time gate | `terraform show -json` + `jq` | assert caller config satisfies controls at plan time (`scripts/plan-gate.sh`) |

The structural layer is driven by composable **transformation units**: atomic
[`mapotf`](https://github.com/Azure/mapotf) rule sets at
`transformations/<unit>/{_default,<module>}/rules.mptf.hcl`, where `_default/`
holds generic rules that apply to *any* module and `<module>/` holds
module-specific rules that mirror the upstream module's directory layout (e.g.
`<unit>/rds/modules/db_instance/`). A **framework** is a named bundle of units,
declared in `frameworks/<framework>.hcl` with a `description` and a
`transformations = [...]` list. The build engine `scripts/patch-module.sh`
either expands a framework manifest to its unit list, or takes an explicit
`TRANSFORMATIONS=a,b` env list — both feed the same engine. All tools ship
bundled inside the `registry-api` image, so the same binary serves requests and
builds modules on demand.

The transformation-unit vocabulary:

| Unit | Kind | What it does |
|---|---|---|
| `destroy` | generic | `prevent_destroy` on all resources |
| `tags` | generic | `ignore_changes = [tags]` on resources that have tags |
| `avm-secure-defaults` | generic | Azure AVM secure variable defaults |
| `aws-secure-defaults` | generic | terraform-aws-modules secure variable defaults + aws data-source injection |
| `aws-s3-public-access` | AWS structural | harden S3 public-access settings |
| `aws-rds-harden` | AWS structural | harden RDS instances |
| `aws-eks-audit-logs` | AWS structural | enable EKS audit logging |
| `aws-vpc-flow-logs` | AWS structural | enable VPC flow logs |
| `aws-s3-checks-cis` / `aws-s3-checks-iso27001` / `aws-s3-checks-soc2` | framework S3 plan-time checks | per-framework S3 `check` blocks |

### Two ways to consume

Both modes serve the **same** hardened module — they differ only in how the
transformation set is chosen and whether the request is gated.

- **Framework subdomain (registry protocol):** Terraform Module Registry
  Protocol, gated by token + framework entitlement. The framework names the
  bundle of units; the subdomain selects the framework. Uses a registry source
  with a separate `version` argument:

  ```hcl
  source  = "cis.conformer.local/<ns>/<name>/<provider>"
  version = "5.11.0"
  ```

  Subdomains: `cis` / `iso27001` / `soc2`.

- **Direct go-getter mode (ad-hoc, open):** framework-less and ungated — a
  convenience, not a control. The transformation set rides the query string of a
  go-getter HTTP source, so there is **no** `version =` argument (the version is
  a query param). Unit names are sanitized to `[A-Za-z0-9_-]` and are
  order-independent (canonical cache key):

  ```hcl
  source = "https://conformer.local/m/<ns>/<name>/<provider>?version=X&transformation=tags,destroy"
  ```

  This is **not** the registry protocol — no `terraform login`, no entitlement.
  See [`examples/direct-transform/`](examples/direct-transform/).

These map onto the enforcement spectrum:

- **Model A — registry (the Compose stack):** the transform runs server-side —
  either pre-built by the Compose builder (`./build.sh`) or on demand at first
  request (dynamic build) — and the hardened zip is stored in MinIO and served
  via the Registry Protocol. Consumers use plain `terraform`; enforcement is
  mandatory and server-gated.
- **Model B — direct (no registry, no fork):** the *same* `rules.mptf.hcl` are
  applied on the consumer side at plan time with `mapotf transform`. Zero server
  infra, but opt-in (a convenience, not a control). See
  [`examples/consumer-side-mapotf/`](examples/consumer-side-mapotf/).

## Prerequisites

- Docker + Docker Compose
- `terraform` or `tofu` to consume the registry

That's the whole list — the registry, storage, proxy/TLS, and the build pipeline
all run as containers in the Compose stack.

## Installation

[`compose/`](compose/) is the entire deployment. Bring up the stack:

```bash
cd compose
cp .env.example .env          # set STATIC_TOKENS to your own secret
docker compose up -d --build
```

This starts `registry-api`, `versitygw` (the registry-api creates the `modules`
bucket on first start), and `caddy`. With `DYNAMIC_BUILD=true` (the default) any upstream module
is fetched, patched, and cached on first request — no pre-build needed. To warm
the cache or pre-build explicitly:

```bash
./build.sh cis_v600 s3-bucket 5.11.0
```

### Local DNS + TLS (one-time)

Terraform requires HTTPS for registry hosts. Caddy serves `*.conformer.local`
and the apex with its internal CA:

```bash
# point the subdomains AND the apex (for direct go-getter mode) at localhost
sudo sh -c 'echo "127.0.0.1 conformer.local cis.conformer.local iso27001.conformer.local soc2.conformer.local" >> /etc/hosts'

# trust Caddy's local CA so Terraform accepts the cert
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
# macOS:
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./caddy-root.crt
```

See [`compose/README.md`](compose/README.md) for the full deployment guide,
including the Linux CA-trust steps, auth modes, and a no-Terraform API check.

## Usage

### Authenticate with the registry

Static-token auth (the default) has no `terraform login` — pass the token via an
env var (host dots → underscores), entitled to the framework in `STATIC_TOKENS`:

```bash
export TF_TOKEN_cis_conformer_local=dev-token-changeme
```

The direct `/m/...` go-getter mode is ungated and needs no token.

### Use a compliance module

```hcl
# main.tf
module "s3_bucket" {
  source  = "cis.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"

  bucket = "my-compliant-bucket"

  # These are enforced by CIS patches — setting to false will fail at plan time
  cis_enforce_encryption   = true
  cis_enforce_ssl_only     = true
  cis_block_public_access  = true
  cis_enforce_versioning   = true
  cis_enforce_logging      = true
}
```

```bash
terraform init   # Downloads the CIS-patched module from the registry
terraform plan   # Compliance validations run at plan time
```

### Switch frameworks

Same module, different framework — just change the subdomain:

```hcl
# ISO 27001 variant
module "s3_bucket" {
  source  = "iso27001.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"
  # ...
}

# SOC 2 variant
module "s3_bucket" {
  source  = "soc2.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"
  # ...
}
```

## Building Compliance Modules

### Pre-build a module

The one-shot builder runs the layered pipeline and uploads the hardened zip to
MinIO (`framework module version`):

```bash
cd compose
./build.sh cis_v600 s3-bucket 5.11.0
./build.sh soc2     s3-bucket 5.11.0
```

With `DYNAMIC_BUILD=true` (the default) this is optional — the registry builds
and caches any requested module on first use.

### Adding rules for a new module

1. Add module-specific rules to the relevant transformation unit(s):
   `transformations/{unit}/{module}/rules.mptf.hcl` (mirroring the upstream
   module's dir layout), with an optional `patch.hcl` advisory toggle in the
   unit dir. Generic rules live under `transformations/{unit}/_default/`.
2. Request the module (dynamic mode picks up the new rules immediately) or
   pre-build it with `./build.sh`.

### Adding a new transformation unit

1. Create `transformations/{unit}/` with `_default/` and/or per-module
   `rules.mptf.hcl` (plus an optional `patch.hcl` for advisory toggles)
2. Reference the unit from one or more framework manifests' `transformations`
   list, or apply it ad-hoc via `TRANSFORMATIONS=` / the direct go-getter query

### Adding a new framework

1. Create `frameworks/{name}.hcl` with a `description` and a
   `transformations = [...]` bundle of unit names
2. Entitle a token to it in `STATIC_TOKENS` (or, for external Keycloak, add the
   matching `framework:{name}` entitlement to the token claims). The `{name}`
   subdomain resolves through Caddy's wildcard proxy automatically.

## Project Structure

```
conformer/
├── docs/                           # Strategy + technique + consuming guides
├── compose/                        # Docker Compose stack — the whole product
│   ├── docker-compose.yml          # registry-api + versitygw + caddy + builder
│   ├── Caddyfile                   # wildcard proxy + automatic local TLS
│   ├── .env.example                # STATIC_TOKENS, DYNAMIC_BUILD, …
│   ├── build.sh                    # one-shot pre-build (framework module version)
│   ├── build-module.sh             # builder entrypoint
│   └── README.md                   # full deployment guide
├── registry-api/                   # Go service (TF Registry Protocol) + bundled toolkit
│   ├── main.go
│   ├── build.go
│   ├── go.mod
│   └── Dockerfile                  # tofu+mapotf+hcledit+jq+gitleaks + the Go binary
├── transformations/                # Atomic, composable transformation units
│   ├── destroy/                    # generic: prevent_destroy on all resources
│   │   └── _default/rules.mptf.hcl
│   ├── tags/                       # generic: ignore_changes=[tags]
│   ├── avm-secure-defaults/        # generic: Azure AVM secure defaults
│   ├── aws-secure-defaults/        # generic: aws-modules secure defaults + data sources
│   ├── aws-s3-public-access/       # AWS structural
│   │   └── s3-bucket/rules.mptf.hcl  # mirrors the upstream module dir layout
│   ├── aws-rds-harden/             # AWS structural
│   ├── aws-eks-audit-logs/         # AWS structural
│   ├── aws-vpc-flow-logs/          # AWS structural
│   └── aws-s3-checks-{cis,iso27001,soc2}/  # per-framework S3 plan-time checks
├── frameworks/                     # Named bundles of transformation units
│   ├── cis_v600.hcl                # description + transformations = [...]
│   ├── iso27001.hcl
│   └── soc2.hcl
├── scripts/
│   ├── patch-module.sh             # build engine: framework manifest OR TRANSFORMATIONS=a,b
│   ├── apply-transforms.sh         # Model B: apply a framework's units in place
│   ├── build-dynamic.sh            # on-demand: fetch upstream + patch + cache
│   ├── plan-gate.sh                # plan-time jq compliance gate
│   └── test-rule.sh                # exercise a single transformation rule
└── examples/
    ├── consumer-side-mapotf/       # Model B: patch directly, no registry/fork
    ├── direct-transform/           # Direct go-getter mode: ad-hoc, framework-less
    ├── compose-smoke-test/         # end-to-end check against the Compose stack
    └── terragrunt/                 # Terragrunt: tfr:// (A) + before_hook (B)
```

Terragrunt consumers: see [`examples/terragrunt/`](examples/terragrunt/) for
both the `tfr://` registry source (Model A) and the `before_hook` mapotf
approach (Model B).
