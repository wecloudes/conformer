# Production deployment — DNS, TLS, accessibility

The [`compose/`](../compose/) stack runs Conformer on one host with a local CA
(`tls internal`) and `*.conformer.local` in `/etc/hosts` — perfect for dev, but
remote consumers (other machines, CI) can't resolve those names or trust that
CA. To make the registry **accessible** to real Terraform/Terragrunt projects
you need three things: real DNS, real TLS, and a host-reachable storage endpoint.

## 1. Real DNS

Pick a domain you control, e.g. `conformer.example.com`, and point both the apex
and a wildcard at the host's public IP:

```
conformer.example.com.        A    203.0.113.10
*.conformer.example.com.      A    203.0.113.10
```

- The **wildcard** serves the framework subdomains (`cis.`, `iso27001.`, `soc2.`).
- The **apex** serves the go-getter `/m/` direct path and `/v1/catalog`.

Set the registry's domain so `extractFramework` strips the right suffix:

```bash
# compose/.env
DOMAIN=conformer.example.com
```

## 2. Real TLS

Caddy already does automatic HTTPS — swap `tls internal` for a real issuer.

### Option A — Let's Encrypt wildcard (DNS-01)

A `*.conformer.example.com` cert needs the **DNS-01** challenge, which needs a
Caddy build with your DNS provider's plugin (the stock image has none). Build a
custom Caddy image and give it API creds:

```dockerfile
# compose/Caddyfile.prod is mounted; build Caddy with e.g. the Cloudflare plugin
FROM caddy:2-builder AS build
RUN xcaddy build --with github.com/caddy-dns/cloudflare
FROM caddy:2
COPY --from=build /usr/bin/caddy /usr/bin/caddy
```

```caddyfile
# Caddyfile (prod)
*.conformer.example.com, conformer.example.com {
    tls {
        dns cloudflare {env.CF_API_TOKEN}
    }
    reverse_proxy registry-api:8080
}
```

Provide `CF_API_TOKEN` (scoped to the zone's DNS edit) via the environment.
Caddy renews automatically.

### Option B — bring your own cert (corporate / internal CA)

If you already have a wildcard cert (corporate PKI), mount it and point Caddy at
it — no ACME:

```caddyfile
*.conformer.example.com, conformer.example.com {
    tls /etc/caddy/certs/wildcard.crt /etc/caddy/certs/wildcard.key
    reverse_proxy registry-api:8080
}
```

Consumers must trust the issuing CA (usually already distributed inside a
corporate network).

## 3. Host-reachable storage endpoint (presigned downloads)

This is the production gotcha. The registry returns a **presigned** S3 URL and
the consumer fetches the zip *directly* from that host — and the sigv4 signature
**binds the host**, so `S3_PUBLIC_ENDPOINT` must be exactly the host the consumer
connects to. `localhost:7070` only works on the same machine.

Route versitygw through Caddy on its own public name and presign against it:

```caddyfile
# add to the prod Caddyfile
storage.conformer.example.com {
    tls { dns cloudflare {env.CF_API_TOKEN} }     # or BYO cert
    reverse_proxy versitygw:7070
}
```

```bash
# compose/.env
S3_PUBLIC_ENDPOINT=storage.conformer.example.com
S3_PUBLIC_USE_SSL=true
```

Now presigned URLs are `https://storage.conformer.example.com/modules/...`,
reachable + TLS, and the signature matches because Caddy preserves the `Host`.
Do **not** publish versitygw's `7070` port directly in production — keep it
internal to the compose network and front it with Caddy.

## 4. Firewall / exposure

Publish only Caddy's `80`/`443`. Keep `registry-api:8080` and `versitygw:7070`
on the internal compose network (remove their host `ports:` mappings in prod).

## 5. Multi-tenant auth (optional)

The default is static bearer tokens (`STATIC_TOKENS`). For per-tenant framework
entitlement, run an external OIDC IdP (Keycloak) and set
`AUTH_MODE=keycloak` + `KEYCLOAK_ISSUER` / `KEYCLOAK_JWKS_URL` — the registry
reads the entitled frameworks from the JWT. (The `/m/` direct path and
`/v1/catalog` stay open by design.)

## Consuming from a real project

Once deployed, the source addresses are the same as dev with the real domain:

```hcl
# Terraform — framework subdomain (gated)
module "bucket" {
  source  = "cis.conformer.example.com/terraform-aws-modules/s3-bucket/aws"
  version = "4.1.2"
}

# Terragrunt — tfr:// (see examples/terragrunt/catalog/)
terraform {
  source = "tfr://cis.conformer.example.com/terraform-aws-modules/s3-bucket/aws?version=4.1.2"
}
```

Discover what's available at `https://conformer.example.com/v1/catalog`.
