# Docker Compose deployment

Conformer runs as a single-host Docker Compose stack — the whole registry plus
the hardening pipeline, nothing else to operate.

| Service | Role |
|---|---|
| `registry-api` | Go service: Terraform Module Registry Protocol + the `/m/` direct endpoint; bundles the patch toolkit (tofu/mapotf/hcledit/jq/gitleaks) and builds modules on demand |
| `versitygw` | Versity S3 Gateway (Apache-2.0) — S3 storage for the hardened module zips (POSIX backend) |
| `builder` | one-shot pre-builder (`./build.sh`), same image as `registry-api` (`--profile build`) |
| `caddy` | wildcard reverse proxy + automatic local TLS for `*.conformer.local` (and the apex) |

## 1. Start the stack

```bash
cd compose
cp .env.example .env          # set STATIC_TOKENS to your own secret
docker compose up -d --build
```

This brings up `registry-api`, `versitygw`, and `caddy` (the registry-api creates
the `modules` bucket in versitygw on first start, retrying until it is up).

## 2a. Dynamic patching (default — no pre-build)

`DYNAMIC_BUILD=true` (default in `.env.example`) means you can request **any**
upstream module and it is fetched, patched, and cached on first use. Point
Terraform/Terragrunt at it — see [dynamic patching](../docs/04-dynamic-patching.md):

```hcl
# framework subdomain (gated by token + framework entitlement)
source  = "cis.conformer.local/Azure/avm-res-automation-automationaccount/azurerm"
version = "0.2.0"
```

Or pick an ad-hoc transformation set with no framework (direct go-getter mode,
ungated):

```hcl
source = "https://conformer.local/m/Azure/avm-res-automation-automationaccount/azurerm?version=0.2.0&transformation=tags,destroy"
```

## 2b. Pre-build a module (optional)

Warm the cache or run without dynamic mode:

```bash
./build.sh cis_v600 s3-bucket 5.11.0
./build.sh soc2     s3-bucket 5.11.0
```

Each runs the layered pipeline (sanitize → strip → mapotf → toggles → fmt) and
uploads `…/cis_v600/5.11.0.zip` to MinIO.

## 3. Local DNS + TLS (one-time)

Terraform requires HTTPS for registry hosts. Caddy serves `*.conformer.local`
and the apex with its internal CA.

```bash
# point the subdomains AND the apex (for direct go-getter mode) at localhost
sudo sh -c 'echo "127.0.0.1 conformer.local cis.conformer.local iso27001.conformer.local soc2.conformer.local" >> /etc/hosts'

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

Switch framework = change the subdomain (`soc2.conformer.local`). The token must
be entitled to that framework in `STATIC_TOKENS`. The direct `/m/` mode (section
2a) needs no token.

## Private / VPN-only access

By default Caddy (`80`/`443`) and versitygw (`7070`) bind `0.0.0.0` (public). To
make the registry reachable **only over a VPN**, set `BIND_IP` in `.env` to your
VPN interface IP (e.g. the WireGuard `wg0` address) — every published port then
binds there instead, and the only public port is the VPN's own. Full self-hosted
WireGuard walkthrough: [docs/07-private-vpn-access.md](../docs/07-private-vpn-access.md).

```bash
# .env
BIND_IP=10.13.13.1               # wg0 address
S3_PUBLIC_ENDPOINT=10.13.13.1:7070   # presign host must be VPN-reachable
```

## Auth modes

- **static** (default) — bearer tokens in `STATIC_TOKENS`, mapped to frameworks.
  Service discovery omits the login block; consumers supply the token directly.
  Simple, good for dev / internal use.
- **keycloak** (external) — set `AUTH_MODE=keycloak` and point `KEYCLOAK_ISSUER`
  / `KEYCLOAK_JWKS_URL` at an OIDC IdP you run yourself. The registry validates
  the JWT against its JWKS and reads framework entitlement from the token. This
  stack does not bundle an IdP.

## Discover what's available

`GET /v1/catalog` (open, no token) lists the frameworks (with their unit
bundles + descriptions), all transformation units, and the modules already
hardened + cached:

```bash
curl -sk https://conformer.local/v1/catalog | jq
```

## Quick API check (no Terraform)

```bash
curl -k -H "Authorization: Bearer dev-token-changeme" \
  https://cis.conformer.local/v1/modules/terraform-aws-modules/s3-bucket/aws/versions
```
