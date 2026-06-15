# Enforcement models

The [transformation techniques](01-transformation-techniques.md) define *how* a
module is hardened. This document covers *where* the transform runs and *how
strongly* the result is enforced.

There are two deployment models. They share the same rules
(`patches/<framework>/<module>/rules.mptf.hcl`) — only the place and the
guarantee differ.

## Model A — registry (server-gated)

The transform runs **once**, at build time, in Tekton. The hardened module is
zipped, stored in MinIO, and served via the Terraform Module Registry Protocol.
Consumers use plain `terraform`.

```
        build time (Tekton)                         consume time
  ┌──────────────────────────────┐          ┌──────────────────────────┐
  │ fetch upstream @ tag          │          │ terraform / terragrunt   │
  │ → patch (layers 1–4)          │   zip    │   source = cis.compliance│
  │ → zip                         ├────────► │   .local/.../s3-bucket   │
  │ → upload to MinIO             │  MinIO   │                          │
  └──────────────────────────────┘          │ Registry API:            │
                                             │  • validate Keycloak JWT │
                                             │  • check framework entitlement
                                             │  • presigned MinIO URL   │
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

- Real infrastructure: Kubernetes, MinIO, Keycloak, Tekton, cert-manager,
  wildcard DNS.
- Hardening is baked at build; a new control means a new build + version.

## Model B — direct (opt-in)

The transform runs on the **consumer side**, at plan time, with
`mapotf transform`. The consumer keeps the real upstream `source`; mapotf
rewrites the downloaded copy in place, then `terraform`/`terragrunt` plans
against it.

```
                        consume time (consumer machine / CI)
  ┌────────────────────────────────────────────────────────────────┐
  │ fetch upstream (git / registry)                                  │
  │ → mapotf transform -r --mptf-dir patches/<fw>/<module>           │
  │ → terraform plan -out tfplan                                     │
  │ → scripts/plan-gate.sh tfplan        (layer 5)                   │
  │ → mapotf reset                       (restore upstream)          │
  └────────────────────────────────────────────────────────────────┘
```

**Properties**

- **Zero server infrastructure** — just `mapotf` + `terraform` (+ `jq`) on PATH.
- Reuses the exact same `rules.mptf.hcl` as Model A.
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

 advisory toggle      consumer-run        org-wide hook         server-gated
 variable{validation} mapotf (Model B)    before_hook in        registry (Model A)
 (patch.hcl)          ad hoc              root.hcl + run-all     + token/entitlement
   │                    │                   │                      │
   caller can just      caller chooses      central config, but    consumer cannot
   set it back          to run it           editable by anyone      obtain unhardened
                                            with repo access        module at all
```

- **Advisory toggle** — the `variable { validation }` blocks in `patch.hcl`.
  Documents intent; a caller can flip the default. Treat as guidance only.
- **Consumer-run mapotf** — Model B invoked ad hoc. Hardens *this* run if the
  operator remembers to use it.
- **Org-wide hook** — Model B with the `before_hook` in Terragrunt `root.hcl`,
  driven by `terragrunt run-all` in CI. Units cannot individually opt out;
  someone with repo access can still edit `root.hcl`. See
  [consuming §terragrunt-b](03-consuming.md#terragrunt--model-b-before_hook).
- **Server-gated** — Model A. The consumer physically cannot fetch a
  non-hardened module without a valid token and framework entitlement.

## Decision matrix

| You need… | Use |
|---|---|
| Mandatory hardening for untrusted / external consumers | **Model A** (registry) |
| An entitlement gate (who may use which framework) | **Model A** |
| No server infrastructure, internal/trusted teams | **Model B** (direct) |
| Org-wide enforcement without a registry | **Model B** via `root.hcl` + CI `run-all` |
| Defense in depth | **A** for the source **+** B's `plan-gate` as a drift catch |

## Threat model — what these do *not* do

- **Neither model fixes a misconfigured *deployment*.** They harden module
  *source* and assert at *plan*. They cannot stop someone who applies a
  different module, edits state directly, or changes resources out of band. Pair
  with runtime detection (AWS Config, CloudTrail, Prowler).
- **Model B is convenience, not a boundary.** If your threat model includes a
  consumer who *wants* to avoid compliance, only Model A (or another hard
  control) stops them.
- **The advisory `variable` toggles enforce nothing on the resources** — they
  are self-referential flags. Real enforcement is the `mapotf` structural layer
  plus the plan-gate. Do not mistake a green `terraform validate` on the toggles
  for a compliant plan.
- **Plan-time checks see only what is planned.** A control depending on data not
  present in the plan (e.g. an external bucket policy) is out of scope for
  `plan-gate.sh`.
