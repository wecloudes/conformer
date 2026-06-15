# Docker Compose deployment (simple)

A single-host alternative to the Kubernetes/Helm stack. Same registry, same
hardening pipeline, far less to run:

| K8s component | Compose equivalent |
|---|---|
| Registry API (Deployment) | `registry-api` container |
| MinIO (Bitnami chart) | `minio` container + `minio-init` |
| Keycloak (Bitnami chart) | **dropped by default** — static-token auth; optional `--profile keycloak` |
| Tekton pipeline | `builder` one-shot container (`./build.sh`) |
| nginx-ingress + cert-manager | `caddy` (wildcard reverse proxy + auto local TLS) |

## 1. Start the stack

```bash
cd compose
cp .env.example .env          # set STATIC_TOKENS to your own secret
docker compose up -d
```

This brings up `registry-api`, `minio`, `minio-init` (creates the `modules`
bucket), and `caddy`.

## 2a. Dynamic patching (default — no pre-build)

`DYNAMIC_BUILD=true` (default in `.env.example`) means you can request **any**
upstream module and it is fetched, patched for the subdomain's framework, and
cached on first use. Just point Terraform/Terragrunt at it — see
[dynamic patching](../docs/04-dynamic-patching.md):

```hcl
source = "cis.conformer.local/Azure/avm-res-automation-automationaccount/azurerm"
version = "0.2.0"
```

## 2b. Pre-build a module (optional)

Warm the cache or run without dynamic mode. Replaces the Tekton PipelineRun:

```bash
./build.sh cis_v600 s3-bucket 5.11.0
./build.sh soc2     s3-bucket 5.11.0
```

Each runs the layered pipeline (sanitize → strip → mapotf → toggles → fmt) and
uploads `…/cis_v600/5.11.0.zip` to MinIO.

## 3. Local DNS + TLS (one-time)

Terraform requires HTTPS for registry hosts. Caddy serves `*.conformer.local`
with its internal CA.

```bash
# point the subdomains at localhost
sudo sh -c 'echo "127.0.0.1 cis.conformer.local iso27001.conformer.local soc2.conformer.local auth.conformer.local" >> /etc/hosts'

# trust Caddy's local CA so Terraform accepts the cert
docker compose cp caddy:/data/caddy/pki/authorities/local/root.crt ./caddy-root.crt
# macOS:
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ./caddy-root.crt
# Linux (Debian/Ubuntu):
sudo cp ./caddy-root.crt /usr/local/share/ca-certificates/caddy-local.crt && sudo update-ca-certificates
```

## 4. Consume it

Static mode has no `terraform login`; pass the token via env var (host with dots
→ underscores):

```bash
export TF_TOKEN_cis_conformer_local=dev-token-changeme
```

```hcl
module "s3_bucket" {
  source  = "cis.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"
  bucket  = "my-compliant-bucket"
}
```

```bash
terraform init    # pulls the CIS-hardened zip from the registry
terraform plan
```

Switch framework = change the subdomain (`soc2.conformer.local`). The token
must be entitled to that framework in `STATIC_TOKENS`.

## Auth modes

- **static** (default) — bearer tokens in `STATIC_TOKENS`, mapped to frameworks.
  No Keycloak. Service discovery omits the login block; consumers supply the
  token directly. Simple, good for dev / internal use.
- **keycloak** — set `AUTH_MODE=keycloak`, run `docker compose --profile keycloak up -d`,
  drop a realm export in `compose/keycloak-realm/`. Enables `terraform login`
  and full OIDC entitlement, matching the K8s stack.

## Quick API check (no Terraform)

```bash
curl -k -H "Authorization: Bearer dev-token-changeme" \
  https://cis.conformer.local/v1/modules/terraform-aws-modules/s3-bucket/aws/versions
```
