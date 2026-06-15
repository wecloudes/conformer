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
| [MinIO server](https://github.com/minio/minio) | AGPL-3.0 | run unmodified via the official image — no source obligation; not redistributed by us |
| [Keycloak](https://github.com/keycloak/keycloak) | Apache-2.0 | optional |
| [Caddy](https://github.com/caddyserver/caddy) | Apache-2.0 | |
| nginx-ingress, cert-manager, Tekton (K8s) | Apache-2.0 | |

## Decisions that keep us clean

- **Terraform → OpenTofu.** HashiCorp Terraform is BUSL-1.1 (use/redistribution
  restricted for "competing" products). We bundle + distribute the binary, so we
  use **OpenTofu (MPL-2.0)** instead. Module sources are always fully qualified
  to `registry.terraform.io`, so OpenTofu fetches the same modules/versions the
  Terraform registry serves (OpenTofu's own registry does not mirror everything,
  e.g. Azure AVM). Provider resolution is avoided on the build path
  (`SKIP_VALIDATE` default) so the OpenTofu provider registry is never required.
- **No bundled `mc`.** MinIO's `mc` CLI is AGPL-3.0. We do not bundle it; uploads
  go through the **minio-go SDK (Apache-2.0)** from the registry-api binary
  (`registry-api upload`), and the bucket is created on startup via the SDK.
- **MinIO server** stays AGPL but is run as an unmodified upstream image; running
  (not modifying/redistributing) AGPL software carries no source obligation. Swap
  for any S3-compatible backend if even that is unacceptable in your context.
