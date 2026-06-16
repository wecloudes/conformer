# Third-party licenses

Conformer bundles and depends on the following components. All are permissive
or weak-copyleft; none impose copyleft on Conformer's own code, and we ship no
BUSL-licensed or bundled AGPL binaries.

## Tools bundled in our images

| Tool | License | Use | Notes |
|---|---|---|---|
| [OpenTofu](https://github.com/opentofu/opentofu) | MPL-2.0 | module fetch (`tofu get`), `fmt` | replaces HashiCorp Terraform |
| [mapotf](https://github.com/Azure/mapotf) | MIT | structural transforms (generic + module-specific) | |
| [hcledit](https://github.com/minamijoyo/hcledit) | MIT | targeted HCL edits | |
| [gitleaks](https://github.com/gitleaks/gitleaks) | MIT | secret scan | |

## Go dependencies (registry-api)

| Module | License |
|---|---|
| [minio-go](https://github.com/minio/minio-go) | Apache-2.0 |
| [MicahParks/keyfunc](https://github.com/MicahParks/keyfunc) | Apache-2.0 |
| [golang-jwt/jwt](https://github.com/golang-jwt/jwt) | MIT |

## Runtime services (unmodified official images)

| Service | License | Notes |
|---|---|---|
| [versitygw](https://github.com/versity/versitygw) (Versity S3 Gateway) | Apache-2.0 | S3 storage, POSIX backend — replaced MinIO (AGPL) so the stack ships no AGPL |
| [Caddy](https://github.com/caddyserver/caddy) | Apache-2.0 | wildcard reverse proxy + local TLS |
| [Keycloak](https://github.com/keycloak/keycloak) | Apache-2.0 | optional, external — only if you run OIDC auth yourself |

## Decisions that keep us clean

- **Terraform → OpenTofu.** HashiCorp Terraform is BUSL-1.1 (use/redistribution
  restricted for "competing" products). We bundle + distribute the binary, so we
  use **OpenTofu (MPL-2.0)** instead. Module sources are always fully qualified
  to `registry.terraform.io`, so OpenTofu fetches the same modules/versions the
  Terraform registry serves (OpenTofu's own registry does not mirror everything,
  e.g. Azure AVM). Provider resolution is avoided on the build path
  (`SKIP_VALIDATE` default) so the OpenTofu provider registry is never required.
- **S3 storage: versitygw, not MinIO.** MinIO server is AGPL-3.0; we use the
  **Versity S3 Gateway (Apache-2.0)** instead, so the running stack ships **no
  AGPL** at all. Its POSIX backend maps buckets to directories.
- **No bundled `mc`.** MinIO's `mc` CLI is AGPL-3.0; we never used it. The S3
  client is the **minio-go SDK (Apache-2.0)** — a generic S3 client library, not
  the MinIO server — so uploads (`registry-api upload`) and the startup bucket
  create go through the SDK against versitygw (or any S3-compatible endpoint).
