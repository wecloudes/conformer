# Transformation catalog

Real-world transformations to encode in Conformer, grouped by intent. Each entry
gives the **control**, the **resource**, the **rule**, and the **effect**.

## Mental model — pick the engine by scope

| You want to… | Engine | Where |
|---|---|---|
| Touch **every** resource (or every resource of a type) in any module | **mapotf** (`data "resource"` + `for_each`) | `patches/<fw>/_default/rules.mptf.hcl` |
| Touch **one named** resource in a specific module | **mapotf** with an explicit `target_block_address` | `patches/<fw>/<module>/…` |

Three questions decide a rule: **which resource** (type or address), **which
attribute/block**, and **force it** (override caller) vs **assert it** (fail at
plan). Force = `update_in_place`/`override`. Assert = a `check` block + the jq
plan-gate.

**Authoring loop:** after editing a rule, validate it without the full stack:

```bash
make lint                                  # HCL fmt + script syntax + go build
make test-rule FW=cis_v600 NS=terraform-aws-modules MODULE=vpc PROVIDER=aws VERSION=5.13.0
```

`make test-rule` fetches the real module, applies the current packs, and prints
the resulting compliance lines + an fmt check.

Each `lifecycle`/attribute rule emits **one** block per resource — split tagged
vs untagged (or by type) so you never add an attribute a resource lacks (that is
a plan error).

---

## 1. Lifecycle protection

**Control:** prevent accidental deletion of stateful infra (CIS data-protection,
SOC2 CC8.1 change management). **Resources:** any stateful — buckets, DBs, key
vaults, disks.

```hcl
# generic: every resource in the module (already in _default)
transform "update_in_place" prevent_destroy {
  for_each             = try(toset(local.addresses), [])
  target_block_address = each.value
  asstring { lifecycle { prevent_destroy = true } }
}
```

Narrower (only databases), in a module-specific file:

```hcl
data "resource" db { resource_type = "aws_db_instance" }
transform "update_in_place" db_protect {
  for_each             = try(data.resource.db.result.aws_db_instance, {})
  target_block_address = each.value.mptf.block_address
  asstring { lifecycle { prevent_destroy = true } }
}
```

## 2. Ignore exogenous tag drift

**Control:** tags applied out-of-band (Azure Policy, org automation) must not
force diffs. **Resource:** anything with `tags` (already in `_default`).

```hcl
# tagged resources only — see _default/rules.mptf.hcl
asstring { lifecycle { ignore_changes = "[tags]" } }
```

## 3. Encryption at rest

**Control:** CIS 2.1.1 / ISO A.8.24 / SOC2 CC6.1. **Resources & attributes:**

| Resource | Force |
|---|---|
| `aws_db_instance` | `storage_encrypted = true` |
| `aws_ebs_volume` | `encrypted = true` |
| `azurerm_storage_account` | `infrastructure_encryption_enabled = true` |
| `aws_s3_bucket_server_side_encryption_configuration` | rule → `sse_algorithm = "aws:kms"` (ISO requires KMS, not AES256) |

```hcl
data "resource" db { resource_type = "aws_db_instance" }
transform "update_in_place" rds_encrypt {
  for_each             = try(data.resource.db.result.aws_db_instance, {})
  target_block_address = each.value.mptf.block_address
  asraw { storage_encrypted = true }
}
```

## 4. Block public access

**Control:** CIS 3.3 / ISO A.8.3 / SOC2 CC6.1.

| Resource | Force |
|---|---|
| `aws_s3_bucket_public_access_block` | all four flags `true` (see `cis_v600/s3-bucket`) |
| `aws_db_instance` | `publicly_accessible = false` |
| `azurerm_storage_account` | `public_network_access_enabled = false` |
| `azurerm_key_vault` | `public_network_access_enabled = false` |

```hcl
data "resource" sa { resource_type = "azurerm_storage_account" }
transform "update_in_place" sa_private {
  for_each             = try(data.resource.sa.result.azurerm_storage_account, {})
  target_block_address = each.value.mptf.block_address
  asraw { public_network_access_enabled = false }
}
```

## 5. Transport security (TLS)

**Control:** CIS 2.1.2 / ISO A.8.24 / SOC2 CC6.7.

| Resource | Force |
|---|---|
| `azurerm_storage_account` | `min_tls_version = "TLS1_2"`, `https_traffic_only_enabled = true` |
| `azurerm_mssql_server` | `minimum_tls_version = "1.2"` |
| `aws_s3_bucket_policy` | inject a deny-non-TLS statement (or assert `attach_deny_insecure_transport_policy`) |

```hcl
data "resource" sa { resource_type = "azurerm_storage_account" }
transform "update_in_place" sa_tls {
  for_each             = try(data.resource.sa.result.azurerm_storage_account, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    min_tls_version            = "TLS1_2"
    https_traffic_only_enabled = true
  }
}
```

## 6. Logging & audit

**Control:** CIS 2.1.4 / ISO A.8.15 / SOC2 CC7.2. Often a *new* resource rather
than an attribute — inject one bound to the target:

```hcl
# inject a diagnostic setting for every storage account (mapotf new_block)
transform "new_block" sa_diag {
  new_block_type = "resource"
  filename       = "_compliance_logging.tf"
  labels         = ["azurerm_monitor_diagnostic_setting", "conformer_audit"]
  asraw {
    name               = "conformer-audit"
    target_resource_id = "PLACEHOLDER"   # wire to the SA id in a module-specific rule
  }
}
```

For attributes you can only know at plan time, prefer an **assert** (`check` +
plan-gate) over forcing — see §10.

## 7. Versioning & retention

**Control:** CIS 2.1.3 / ISO A.8.25 / SOC2 CC8.1.

| Resource | Force |
|---|---|
| `aws_s3_bucket_versioning` | `versioning_configuration { status = "Enabled" }` |
| `azurerm_key_vault` | `purge_protection_enabled = true`, `soft_delete_retention_days = 90` |
| `aws_db_instance` | `backup_retention_period >= 7`, `deletion_protection = true` |

## 8. Mandatory tags (merge, don't clobber)

**Control:** governance / cost allocation. Add org tags while preserving the
module's own. Do it with a mapotf `update_in_place` that re-emits `tags` wrapped
in `merge()`, so the module's existing tag source is kept:

```hcl
# patches/<fw>/<module>/rules.mptf.hcl — merge org tags, keep existing
data "resource" sa {
  resource_type = "azurerm_storage_account"
}

transform "update_in_place" merge_org_tags {
  for_each             = try(data.resource.sa.result.azurerm_storage_account, {})
  target_block_address = each.value.mptf.block_address

  asraw {
    tags = merge(var.tags, {
      owner               = "platform"
      data_classification = "internal"
    })
  }
}
```

> Preserving the module's own tags depends on the module passing a `tags`
> variable (`var.tags`) through to the resource — the common AVM / terraform-aws
> convention. If a module hardcodes literal tags on the block, target that
> resource explicitly and reproduce the literals in the `merge()` first arg.

## 9. Removal & sanitization

**Control:** strip dangerous or leaky constructs. **Patterns:**

- `provisioner` / `local-exec` blocks → removed (awk, in `patch-module.sh`).
- hardcoded account IDs / regions → `data.aws_caller_identity` / `data.aws_region` (sed).
- secrets → `gitleaks` (report or block).
- a deprecated/insecure attribute → `remove_block_element` (mapotf).

## 10. Plan-time assertions (when you can't force)

**Control:** anything depending on caller values that resolve only at plan time.
Inject a `check` block and let `scripts/plan-gate.sh` fail CI:

```hcl
transform "new_block" assert_encryption {
  new_block_type = "check"
  filename       = "_compliance_assert.tf"
  labels         = ["encryption_required"]
  asraw {
    assert {
      condition     = length(keys(var.server_side_encryption_configuration)) > 0
      error_message = "[CIS 2.1.1] encryption must be configured."
    }
  }
}
```

## 11. Inject a data source — and use its output

`new_block` adds a Terraform `data` source to the module without forking; pair it
with `update_in_place` to wire the looked-up attribute into a resource. This lets
you enforce values that must be *discovered* (an org KMS key, the caller account,
an AMI) rather than hardcoded.

Example — force a company-managed KMS key (looked up by alias) onto S3 encryption:

```hcl
# 1. inject the data source
transform "new_block" org_cmk {
  new_block_type = "data"
  filename       = "_conformer_data.tf"
  labels         = ["aws_kms_key", "conformer_cmk"]
  body           = <<-BODY
    key_id = "alias/conformer-compliance"
  BODY
}

# 2. use its output on the encryption resource
data "resource" sse {
  resource_type = "aws_s3_bucket_server_side_encryption_configuration"
}

transform "update_in_place" use_cmk {
  for_each             = try(data.resource.sse.result.aws_s3_bucket_server_side_encryption_configuration, {})
  target_block_address = each.value.mptf.block_address
  asstring {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
        # asstring emits the string as raw tokens, so this becomes a real
        # reference, not a quoted literal:
        kms_master_key_id = "data.aws_kms_key.conformer_cmk.arn"
      }
    }
  }
}
```

**Guard duplicates:** if the module may already declare the data source, gate the
`new_block` with a `for_each` over a `data "data"` presence check (keyed by
type → label) so you don't hit a duplicate-address error.

**Shipped use of this pattern:** `patch-module.sh` rewrites hardcoded account IDs
/ regions to `data.aws_caller_identity.current` / `data.aws_region.current`;
`_default/aws-datasources.mptf.hcl` injects those data sources so the rewrite
never dangles — guarded so it only fires on AWS modules (`aws_*` resources
present) that don't already declare them. Tested: injected on an AWS module with
a hardcoded ARN, skipped on an AVM module.

---

## Choosing force vs assert

- **Force** (`update_in_place`/`override`) when the secure value is absolute and
  caller-independent (public access off, TLS 1.2, prevent_destroy). The caller
  *cannot* get it wrong.
- **Assert** (`check` + plan-gate) when the value is legitimately caller-supplied
  but must meet a bar (an approved instance type, a logging target). The caller
  picks; you verify.
- Forcing an attribute a resource doesn't have, or that the caller didn't set, is
  a plan error — always scope `for_each` by resource type and (for nested attrs)
  by presence.

## Where each lives

| Scope | File |
|---|---|
| Every module, every framework | `patches/<fw>/_default/rules.mptf.hcl` |
| One module, one framework | `patches/<fw>/<module>/rules.mptf.hcl` (+ `patch.hcl` toggles) |
| Plan-time gate | `scripts/plan-gate.sh` |

---

---

# Provider-family transformations

Both families standardize names, so **one rule can cover a whole family**. Two
hard limits shape how:

- **mapotf sees only the dir it runs in.** `data "resource"` finds resources in
  the module's own files. For **flat** modules (AVM, `terraform-aws-s3-bucket` —
  resources at the root) you can override the *resource* directly (HARD). For
  **wrapper** modules (`terraform-aws-rds/vpc/eks` — real resources in local
  `modules/…` submodules) `data "resource"` does **not** reach them; override the
  root **pass-through variable** defaults instead (SOFT).
- **Address-targeted transforms error if the target is absent.**
  `update_in_place "variable.x"` / `remove_block "resource.y"` fail when the
  block doesn't exist. Only `for_each` over a `data` query is a true no-op. So in
  a shared `_default`, **guard every address target** with a presence check.

The guard pattern (used by both packs below):

```hcl
data "variable" all {
}

locals {
  want    = ["enable_telemetry", "local_authentication_enabled"]
  present = [for v in local.want : v if contains(keys(try(data.variable.all.result, {})), v)]
}

transform "update_in_place" secure_defaults {
  for_each             = try(toset(local.present), [])
  target_block_address = "variable.${each.value}"
  asraw {
    default = false
  }
}
```

> Each `*.mptf.hcl` in a `--mptf-dir` is merged, so `data`/`locals` names must be
> unique across files (e.g. `data "variable" all` in `avm.mptf.hcl`,
> `data "variable" awv` in `aws-modules.mptf.hcl`).

## Azure Verified Modules (`avm-res-*`) — shipped: `_default/avm.mptf.hcl`

Every AVM module shares one interface (verified). Secure defaults, SOFT, guarded:

| Variable (constant across AVM) | Forced default | Why |
|---|---|---|
| `enable_telemetry` | `false` | privacy; also count-gates the telemetry resources |
| `local_authentication_enabled` | `false` | force Entra ID, disable shared keys |
| `public_network_access_enabled` | `false` | private by default |

Tested on `avm-res-automation-automationaccount@0.2.0`: all three flipped, and a
no-op (no error) on a non-AVM module. Advanced/HARD options (mention, not
shipped): remove `modtm_telemetry.telemetry` outright; default `var.lock` to
`CanNotDelete`; assert `var.diagnostic_settings`/`var.customer_managed_key` via a
`check` block + plan-gate.

## terraform-aws-modules (Babenko) — shipped: `_default/aws-modules.mptf.hcl`

Wrapper modules → root variable-default overrides (SOFT), guarded:

| Variable | Forced default | Module |
|---|---|---|
| `storage_encrypted` | `true` | rds |
| `deletion_protection` | `true` | rds |
| `iam_database_authentication_enabled` | `true` | rds |
| `performance_insights_enabled` | `true` | rds |
| `publicly_accessible` | `false` | rds |
| `enable_flow_log` / `create_flow_log_cloudwatch_log_group` | `true` | vpc (CIS 3.9) |
| `cluster_endpoint_public_access` | `false` | eks |

Tested on `terraform-aws-rds@6.10.0`: all five rds defaults flipped via the root
pass-through vars.

**Flat modules get HARD overrides.** `terraform-aws-s3-bucket` keeps its resources
at the root, so `cis_v600/s3-bucket/rules.mptf.hcl` overrides the actual
`aws_s3_bucket_public_access_block` resource — the caller cannot weaken it. Use
this resource-level form only when the resource is in the module's own dir:

```hcl
data "resource" pab {
  resource_type = "aws_s3_bucket_public_access_block"
}

transform "update_in_place" block_public {
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

## Hard enforcement for wrapper modules (submodule-targeted rules)

A module-specific rules file **mirrors the module's directory layout**, and
`patch-module.sh` runs mapotf in the matching subpath. So to hard-override a
resource in a local submodule, put the rule at the submodule's path:

```
patches/cis_v600/rds/rules.mptf.hcl                       # runs at the module root
patches/cis_v600/rds/modules/db_instance/rules.mptf.hcl   # runs INSIDE modules/db_instance
```

```hcl
# patches/cis_v600/rds/modules/db_instance/rules.mptf.hcl
data "resource" rds {
  resource_type = "aws_db_instance"
}

transform "update_in_place" rds_harden {
  for_each             = try(data.resource.rds.result.aws_db_instance, {})
  target_block_address = each.value.mptf.block_address
  asraw {
    storage_encrypted                   = true
    deletion_protection                 = true
    publicly_accessible                 = false
    iam_database_authentication_enabled = true
    performance_insights_enabled        = true
  }
}
```

Tested on `terraform-aws-rds@6.10.0`: the attrs on `aws_db_instance.this` become
literal `true`/`false` (were `= var.x`) — the caller cannot weaken them. Pair
with the soft `_default` root-var defaults for defense in depth.

### Shipped hard module rules (AWS)

| Module | Rule path | Resource (where) | Hard override | Soft pair (`_default`) |
|---|---|---|---|---|
| rds | `<fw>/rds/modules/db_instance/` | `aws_db_instance.this` (submodule) | `storage_encrypted`, `deletion_protection`, `publicly_accessible=false`, `iam_database_authentication_enabled`, `performance_insights_enabled` | same vars at root |
| vpc | `<fw>/vpc/` | `aws_flow_log.this` (root) | `traffic_type = "ALL"` (CIS 3.9) | `enable_flow_log=true` |
| eks | `<fw>/eks/` | `aws_eks_cluster.this` (root) | `enabled_cluster_log_types` = full audit set | `cluster_endpoint_public_access=false` |

rds is **submodule-targeted** (rule mirrors `modules/db_instance/`); vpc and eks
keep the controlled resource at the module root, so their rules sit at the module
dir. All three tested on the real modules (v5.13.0 / v6.10.0 / v20.24.0).

## Hard vs soft, by module shape

| Module shape | Example | Override | Strength |
|---|---|---|---|
| Flat (resources at root) | AVM, `terraform-aws-s3-bucket` | resource attribute | **hard** (caller can't weaken) |
| Wrapper (local submodules) | `terraform-aws-rds/vpc/eks` | root variable default | soft (caller can override) |
| Wrapper, **submodule-targeted rule** | `terraform-aws-rds` → `modules/db_instance` | resource attr in the submodule | **hard** |
| Caller-supplied values | security-group rules, instance types | plan-time `check` + `plan-gate.sh` | assert (fail CI) |

## Family-scoped `_default` packs (shipped layout)

mapotf merges every `*.mptf.hcl` in `--mptf-dir`, and the guards make each pack a
no-op where it doesn't apply, so all three run together on every build:

```
patches/<fw>/_default/rules.mptf.hcl           # provider-agnostic: prevent_destroy, ignore tags
patches/<fw>/_default/avm.mptf.hcl             # AVM family: telemetry, local auth, private
patches/<fw>/_default/aws-modules.mptf.hcl     # Babenko family: rds, vpc, eks (soft var-defaults)
patches/<fw>/_default/aws-datasources.mptf.hcl # declares data sources the sanitizer references
```
