# Model B — Direct consumer-side patching (mapotf)

Harden an upstream Terraform module **without forking it and without pushing
anything to the registry**. The same `rules.mptf.hcl` files the registry build
pipeline uses (`patches/<framework>/s3-bucket/rules.mptf.hcl`) are applied here
locally, at plan time.

## How it differs from the registry (Model A)

| | Model A — registry | Model B — this example |
|---|---|---|
| Where transform runs | once, in Tekton at build | on your machine / CI, at plan time |
| Module source | `cis.conformer.local/.../s3-bucket/aws` | real upstream, patched transiently |
| Infra needed | K8s + MinIO + Keycloak + Tekton | just `mapotf` + `terraform` |
| Enforcement | mandatory (server-gated) | **opt-in** — you must run `harden.sh` |
| Best for | regulated / untrusted consumers | internal teams, module authors |

Model B is convenience, not a control: anyone can skip `mapotf` and run plain
`terraform`. If compliance must be *enforced*, use the registry.

## Run it

```bash
# needs: mapotf (github.com/Azure/mapotf), terraform, jq, git
./harden.sh cis_v600 5.11.0
```

What happens:

1. clones `terraform-aws-s3-bucket` v5.11.0 into `./upstream` (transient, not a fork)
2. `mapotf transform` rewrites that checkout in place — injects `prevent_destroy`,
   forces all four public-access flags shut, adds plan-time `check` blocks
3. `terraform plan -out tfplan`
4. `scripts/plan-gate.sh tfplan` — jq asserts encryption / versioning / public
   access on the resources actually being created; non-zero exit fails CI
5. `mapotf reset` restores `./upstream` to pristine upstream

`main.tf` is intentionally non-compliant so you see the gate fire. Fix the
config (add `server_side_encryption_configuration`, `versioning`) and the gate
goes green.
