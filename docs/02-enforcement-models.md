# Enforcement models

The [transformation techniques](01-transformation-techniques.md) define *how* a
module is hardened. This document covers *where* the transform runs and *how
strongly* the result is enforced.

There are two deployment models. They share the same rules — atomic
**transformation units** at `transformations/<unit>/{_default,<module>}/rules.mptf.hcl`
(with optional `patch.hcl` toggles) — only the place and the guarantee differ. A
`_default/` directory holds the generic rules; a `<module>/` directory holds
module-specific ones. A **framework** is a manifest (`frameworks/<framework>.hcl`)
listing `transformations = ["unit", ...]` — a named bundle of units. The same
units drive both models.

## Two control classes: enforcements and assertions

Orthogonal to *where* a control runs (Model A/B above): **every control is one of
two kinds.** This is the whole compliance model in one line — *enforce what you
can control, assert what you can only observe.*

| | **Enforcement (force)** | **Assertion (assert)** |
|---|---|---|
| When the value is… | absolute, caller-independent | caller-supplied, or in an internal module resource a generic force can't reach |
| Mechanism | mapotf rewrites module source **before plan** | verify **at plan**, fail CI |
| The caller… | *cannot* get it wrong | picks the value; we check the bar |
| Implemented by | `update_in_place` / `override` on resources + `lifecycle` meta; secure-default var overrides | in-module `check {}` blocks **and** external `plan-gate.sh` (jq over `terraform show -json`) |
| Units | every `_default/` + `<module>/` `rules.mptf.hcl` (e.g. encryption on, TLS floor, public-access off, `https_only`); `destroy`, `tags`, `avm-secure-defaults`, `aws-secure-defaults` | `aws-s3-checks-<fw>` (in-module) + the `plan-gate.sh` asserts (external) |

The deciding rule: **value absolute → enforce; value caller's or plan-only →
assert.** Forcing a caller-supplied value would either break the module or be
silently overridden; asserting an absolute value is just a weaker way to enforce
it. (The advisory `variable { validation }` toggles in `patch.hcl` are *opt-outs
on the enforcement side*, not a third class — see the spectrum below.)

### Assertions have two homes

- **In-module `check {}`** — shipped as a `*-checks-<fw>` unit, injected into the
  module so the assertion travels with the source. Today: `aws-s3-checks-<fw>`
  (per-framework S3 control IDs).
- **External `plan-gate.sh`** — `jq` over the saved plan. Catches what no
  source-time force can reach: caller-supplied values that resolve only at plan
  time (S3 SSE / versioning / public-access) and **internal module resources**
  (ALB listener, WAF association, API Gateway stage; Azure App Gateway, APIM,
  NSG). Run `scripts/plan-gate.sh tfplan <framework>` — the framework arg only
  swaps the clause IDs printed; the assertions are identical.

## Enforcements and assertions per framework

Every framework is a **bundle of enforcement units** plus the **assertions** that
cover the controls a force can't. The nine cross-cloud frameworks share an
identical enforcement set (43 units: 4 generic/meta + 23 AWS force + 16 Azure
force) and differ only in their one in-module S3 check unit and the clause IDs
their plan-gate run prints. The **ENS** family is split by cloud: `ens` is
Azure-only (no AWS units, no S3 check unit), while `ens_low` / `ens_medium` /
`ens_high` are the AWS CCN-ENS conformance-pack levels — an AWS-only force-able
subset (17 units + `aws-s3-checks-ens`). The three AWS levels bundle the same
units: the CCN-ENS packs are ~identical (112/113/114 Config rules) and differ
only in detective rules outside source-time forcing.

| Framework | Enforcement units | In-module assert unit | Plan-gate asserts (always 11: 3 S3 + 4 AWS-edge + 4 Azure) |
|---|---|---|---|
| `cis_v600` | 43 (generic + AWS + Azure) | `aws-s3-checks-cis` | ✓ tagged below |
| `iso27001` | 43 | `aws-s3-checks-iso27001` | ✓ |
| `soc2` | 43 | `aws-s3-checks-soc2` | ✓ |
| `pci_dss` | 43 | `aws-s3-checks-pci` | ✓ |
| `hipaa` | 43 | `aws-s3-checks-hipaa` | ✓ |
| `nist_800_53` | 43 | `aws-s3-checks-nist` | ✓ |
| `fedramp` | 43 | `aws-s3-checks-fedramp` | ✓ |
| `gdpr` | 43 | `aws-s3-checks-gdpr` | ✓ |
| `nis2` | 43 | `aws-s3-checks-nis2` | ✓ |
| `ens` | 19 (generic + Azure only) | — (Azure-only; no S3 unit) | only the 4 Azure asserts fire (no AWS resources in plan) |
| `ens_low` / `ens_medium` / `ens_high` | 17 (generic + AWS subset) | `aws-s3-checks-ens` | the AWS asserts fire (3 S3 + 4 AWS-edge) |

The plan-gate asserts are the same checks for every framework; only the **cited
clause ID** changes per framework (`scripts/plan-gate.sh`'s `cite()`):

| Framework | TLS (ELB / App Gateway) | WAF | Logging (API GW / APIM) | Flow logs (NSG) |
|---|---|---|---|---|
| `cis_v600` | CIS AWS 4.x | CIS AWS 4.x | CIS AWS 4.x | CIS Azure 6.x |
| `iso27001` | ISO 27001 A.8.24 | ISO 27001 A.8.23 | ISO 27001 A.8.15 | ISO 27001 A.8.16 |
| `soc2` | SOC2 CC6.7 | SOC2 CC6.6 | SOC2 CC7.2 | SOC2 CC7.2 |
| `pci_dss` | PCI DSS 4.2.1 | PCI DSS 6.4.2 | PCI DSS 10.2.1 | PCI DSS 10.2.1 |
| `hipaa` | §164.312(e)(1) | §164.312(c)(1) | §164.312(b) | §164.312(b) |
| `nist_800_53` | NIST SC-8 | NIST SC-7 | NIST AU-2 | NIST AU-12 / SC-7 |
| `fedramp` | NIST SC-8 | NIST SC-7 | NIST AU-2 | NIST AU-12 / SC-7 |
| `gdpr` | GDPR Art.32(1)(a) | GDPR Art.32(1)(b) | GDPR Art.30 | GDPR Art.30 |
| `nis2` | NIS2 Art.21(2)(h) | NIS2 Art.21(2)(e) | NIS2 Art.21(2)(i) | NIS2 Art.21(2)(i) |
| `ens` (Azure) | ENS mp.com.3 | ENS mp.com.1 | ENS op.exp.8 | ENS op.exp.8 |
| `ens_low` / `ens_medium` / `ens_high` (AWS) | ENS mp.com.3 | ENS mp.com.1 | ENS op.exp.8 | ENS op.exp.8 |

The three S3 plan-gate asserts (public-access fully blocked, SSE present,
versioning present) are framework-independent and always run; they back the
in-module `aws-s3-checks-<fw>` unit with a plan-level check.

## Model A — registry (server-gated)

The transform runs **once**, at build time, in the compose builder (or on demand
via dynamic build). The hardened module is zipped, stored in versitygw, and served
via the Terraform Module Registry Protocol. Consumers use plain `terraform`.

```
   build time (compose builder)                     consume time
  ┌──────────────────────────────┐          ┌──────────────────────────┐
  │ fetch upstream @ tag          │          │ terraform / terragrunt   │
  │ → patch (layers 1–4)          │   zip    │   source = cis.conformer │
  │ → zip                         ├────────► │   .local/.../s3-bucket   │
  │ → upload to S3                │versitygw │                          │
  └──────────────────────────────┘          │ Registry API:            │
                                             │  • validate token        │
                                             │  • check framework entitlement
                                             │  • presigned S3 URL      │
                                             └──────────────────────────┘
```

**Properties**

- Enforcement is **mandatory**: the consumer cannot get the module without going
  through the API, which checks token + framework entitlement.
- Consumers run unmodified `terraform`; nothing to install, nothing to opt into.
- Centralized audit: every hardened build is one artifact, versioned and
  cacheable.
- The framework is the **subdomain** (`cis.` / `iso27001.` / `soc2.`).

**Costs**

- A Docker Compose stack — registry-api, versitygw, Caddy (wildcard TLS) — plus
  wildcard DNS. Auth is static tokens by default (optional external OIDC).
- Hardening is baked at build; a new control means a new build + version.

**The two consumption modes Model A serves**

The server exposes the hardened module two ways:

1. **Framework subdomain (registry protocol, gated).** The compliance source —
   `source = "cis.conformer.local/<ns>/<name>/<provider>"` with a separate
   `version` argument — speaks the Terraform Module Registry Protocol and is
   gated by a Keycloak token **plus** a framework entitlement. This is the
   server-gated control described above.

2. **Direct go-getter (ad-hoc, framework-less, open / ungated).** The same
   server also serves a bare go-getter HTTP source that carries the
   transformation set in the query string:
   `source = "https://conformer.local/m/<ns>/<name>/<provider>?version=X&transformation=tags,destroy"`.
   The server resolves `?transformation=`, builds only those units, caches the
   result, and returns the zip. This is **not** the registry protocol — there is
   no `terraform login`, no token, no entitlement, and no `version =` argument
   (the version is a query param). It is a **convenience, not a control**:
   because it is ungated, it sits **low** on the enforcement spectrum, right
   next to consumer-run mapotf (Model B). See `examples/direct-transform/`.

## Model B — direct (opt-in)

The transform runs on the **consumer side**, at plan time, with
`mapotf transform`. The consumer keeps the real upstream `source`; mapotf
rewrites the downloaded copy in place, then `terraform`/`terragrunt` plans
against it.

```
                        consume time (consumer machine / CI)
  ┌────────────────────────────────────────────────────────────────┐
  │ fetch upstream (git / registry)                                  │
  │ → mapotf transform -r --mptf-dir transformations/<unit>/<module> │
  │ → terraform plan -out tfplan                                     │
  │ → scripts/plan-gate.sh tfplan        (layer 5)                   │
  │ → mapotf reset                       (restore upstream)          │
  └────────────────────────────────────────────────────────────────┘
```

**Properties**

- **Zero server infrastructure** — just `mapotf` + `terraform` (+ `jq`) on PATH.
- Reuses the exact same transformation units (`rules.mptf.hcl`) as Model A,
  selected directly or via a `frameworks/<framework>.hcl` bundle.
- No fork: upstream is patched transiently and restored.

**Costs**

- **Opt-in, not a control.** Anyone can skip `mapotf` and run plain
  `terraform`. It hardens; it does not *prevent* non-hardened use.
- No entitlement gate — every consumer with the rules can apply any framework.
- Enforcement strength depends entirely on where you place the trigger (see
  spectrum below).

## The enforcement spectrum

Both models are points on a spectrum from "advice" to "cannot be bypassed":

```
weaker ──────────────────────────────────────────────────────► stronger

 advisory toggle      ungated runs        org-wide hook         server-gated
 variable{validation} consumer mapotf     before_hook in        framework registry
 (patch.hcl)          + direct go-getter  root.hcl + run-all     + token/entitlement
   │                    │                   │                      │
   caller can just      caller chooses      central config, but    consumer cannot
   set it back          to run it / asks    editable by anyone      obtain unhardened
                        the open endpoint   with repo access        module at all
```

- **Advisory toggle** — the `variable { validation }` blocks in `patch.hcl`.
  Documents intent; a caller can flip the default. Treat as guidance only.
- **Ungated runs** — Model B's consumer-run `mapotf` invoked ad hoc, **and**
  Model A's direct go-getter endpoint. Both harden *this* run if the operator
  chooses to use them, but neither is gated by a token or entitlement, so both
  sit here: convenience, not a control.
- **Org-wide hook** — Model B with the `before_hook` in Terragrunt `root.hcl`,
  driven by `terragrunt run-all` in CI. Units cannot individually opt out;
  someone with repo access can still edit `root.hcl`. See
  [consuming §terragrunt-b](03-consuming.md#terragrunt--model-b-before_hook).
- **Server-gated** — Model A's framework subdomain (registry protocol). The
  consumer physically cannot fetch a non-hardened module without a valid token
  and framework entitlement. (Model A's direct go-getter endpoint is *not* this
  — it is ungated and sits with the weaker runs above.)

## Decision matrix

| You need… | Use |
|---|---|
| Mandatory hardening for untrusted / external consumers | **Model A** framework subdomain (gated registry) |
| An entitlement gate (who may use which framework) | **Model A** framework subdomain |
| Quick ad-hoc hardening, no token, no framework, internal/trusted | **Model A** direct go-getter (ungated convenience) |
| No server infrastructure, internal/trusted teams | **Model B** (direct) |
| Org-wide enforcement without a registry | **Model B** via `root.hcl` + CI `run-all` |
| Defense in depth | **A** for the source **+** B's `plan-gate` as a drift catch |

## Threat model — what these do *not* do

- **Neither model fixes a misconfigured *deployment*.** They harden module
  *source* and assert at *plan*. They cannot stop someone who applies a
  different module, edits state directly, or changes resources out of band. Pair
  with runtime detection (AWS Config, CloudTrail, Prowler).
- **Model B — and Model A's direct go-getter endpoint — are convenience, not a
  boundary.** Both are ungated: a consumer can skip mapotf, or request a
  different (or empty) `?transformation=` set from the open endpoint. If your
  threat model includes a consumer who *wants* to avoid compliance, only Model
  A's gated framework subdomain (or another hard control) stops them.
- **The advisory `variable` toggles enforce nothing on the resources** — they
  are self-referential flags. Real enforcement is the `mapotf` structural layer
  plus the plan-gate. Do not mistake a green `terraform validate` on the toggles
  for a compliant plan.
- **Plan-time checks see only what is planned.** A control depending on data not
  present in the plan (e.g. an external bucket policy) is out of scope for
  `plan-gate.sh`.
