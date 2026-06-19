# Private (VPN-only) access

By default the stack publishes Caddy (`80`/`443`) and versitygw (`7070`) on
`0.0.0.0` — anyone who can route to the host reaches them. This guide makes the
registry reachable **only over a self-hosted WireGuard VPN**: the sole port open
on the host's public interface is WireGuard's `51820/udp`; every registry port
binds to the VPN interface.

```
                 public internet
                       │  only 51820/udp
                       ▼
   ┌──────────────────────────────────────────────┐
   │ host                                          │
   │  wg0 = 10.13.13.1   (WireGuard interface)     │
   │   ├─ caddy   :443/:80  bound to 10.13.13.1    │
   │   └─ versitygw :7070   bound to 10.13.13.1    │  ← BIND_IP
   │  registry-api :8080  (internal, never published)
   └──────────────────────────────────────────────┘
        ▲ tunnel
   10.13.13.2  laptop / CI runner (WireGuard peer)
```

The single knob in the stack is **`BIND_IP`** (compose/.env): the host address
the published ports bind to. Set it to the wg0 address and the registry vanishes
from every other interface.

## 1. Install WireGuard

Host **and** each client:

```bash
# Debian/Ubuntu
sudo apt install wireguard
# macOS client: `brew install wireguard-tools` or the App Store app
```

## 2. Generate keys

On the host and each client:

```bash
wg genkey | tee server.key | wg pubkey > server.pub   # on the host
wg genkey | tee laptop.key | wg pubkey > laptop.pub    # on the client
```

## 3. Configure the tunnel

Templates are in `compose/wireguard/`. Fill the keys in.

- **Host** → `/etc/wireguard/wg0.conf` from
  [`wg0.server.conf.example`](../compose/wireguard/wg0.server.conf.example)
  (server private key + each client's **public** key).
- **Client** → `/etc/wireguard/wg0.conf` from
  [`wg0.client.conf.example`](../compose/wireguard/wg0.client.conf.example)
  (client private key, server **public** key, server's public IP).

Bring it up on both ends:

```bash
sudo wg-quick up wg0
sudo wg            # shows handshake once the client connects
```

No NAT/forwarding rules are needed — peers talk straight to `10.13.13.1`, where
the registry listens.

## 4. Start the stack bound to the VPN (docker compose)

From the repo root, create `.env` and point the published ports at the wg0
address:

```bash
cp compose/.env.example compose/.env
# edit compose/.env:
#   STATIC_TOKENS=<your-token>=cis_v600,ens_high   # entitlement inside the VPN
#   BIND_IP=10.13.13.1                             # bind every port to wg0
#   S3_PUBLIC_ENDPOINT=10.13.13.1:7070             # presign host must be VPN-reachable
```

`BIND_IP` is the only change versus a public deploy — every published port
(Caddy 80/443, versitygw 7070) binds the VPN interface instead of `0.0.0.0`.
`S3_PUBLIC_ENDPOINT` must also be the VPN host: the S3 signature binds the
hostname, so a `localhost`/public value would not resolve for a remote peer.

Build the image once, then bring it up:

```bash
make image                                        # build conformer-registry-api:latest
docker compose -f compose/docker-compose.yml up -d
```

Confirm the ports left `0.0.0.0`:

```bash
docker compose -f compose/docker-compose.yml ps   # ports show 10.13.13.1:443->443, 10.13.13.1:7070->7070
sudo ss -ltnp | grep -E ':443|:7070'              # LISTEN on 10.13.13.1, NOT 0.0.0.0
```

If `ss` still shows `0.0.0.0:443`, `BIND_IP` was not picked up — re-run `up -d`
after fixing `compose/.env`.

## Add users (WireGuard peers)

Each "user" is a WireGuard peer. The helper
[`compose/wireguard/add-peer.sh`](../compose/wireguard/add-peer.sh) generates a
keypair, registers the peer on the server (live **and** persisted to `wg0.conf`),
auto-assigns the next free tunnel IP, and writes the client config — run it on
the **server**, as root:

```bash
cd compose/wireguard
sudo ENDPOINT=<server-public-ip>:51820 ./add-peer.sh laptop
#   peer 'laptop' added at 10.13.13.2 -> ./laptop.conf
sudo ENDPOINT=<server-public-ip>:51820 ./add-peer.sh ci-runner 10.13.13.7   # explicit IP
```

Hand the printed `<name>.conf` to that user over a secure channel (it holds their
private key — never commit it; `.gitignore` already excludes `wireguard/*.conf`).
On mobile, install `qrencode` on the server and the script prints a scannable QR.

Manual equivalent (no script):

```bash
# on the client: make a keypair, send ONLY the public key to the admin
wg genkey | tee laptop.key | wg pubkey > laptop.pub

# on the server: register the peer (live + persist the same block in wg0.conf)
sudo wg set wg0 peer "$(cat laptop.pub)" allowed-ips 10.13.13.2/32
```

**Remove a user:**

```bash
sudo wg set wg0 peer <THEIR_PUBLIC_KEY> remove   # live
# then delete that [Peer] block from /etc/wireguard/wg0.conf so it doesn't return
```

## Connect a client (laptop / CI)

1. Install WireGuard (step 1).
2. Drop the `<name>.conf` you were given at `/etc/wireguard/wg0.conf`
   (or import it in the GUI app / via the QR).
3. Bring the tunnel up and confirm the handshake:
   ```bash
   sudo wg-quick up wg0
   sudo wg            # "latest handshake" appears within a few seconds
   ping 10.13.13.1    # the registry host over the tunnel
   ```
4. Resolve `*.conformer.local` to the tunnel IP (§5 below) and trust the Caddy CA
   (§6). Then consume the registry exactly as in
   [compose/README.md §Consume](../compose/README.md) — over the VPN it now works,
   off the VPN it does not.

```bash
# quick check over the tunnel:
curl -sk --resolve conformer.local:443:10.13.13.1 https://conformer.local/v1/catalog | jq .domain
```

Tear down with `sudo wg-quick down wg0` when done.

## 5. Client name resolution

Terraform fetches from framework **subdomains** (`cis.conformer.local`,
`ens-high.conformer.local`, …), so clients need wildcard resolution to the
tunnel IP. Two options:

- **dnsmasq on the host** (clean, wildcard). Bind it to `10.13.13.1` with
  `address=/.conformer.local/10.13.13.1`, then set `DNS = 10.13.13.1` in the
  client `[Interface]`.
- **/etc/hosts on the client** (quick, no wildcard — list the subdomains you
  actually use):
  ```
  10.13.13.1  conformer.local cis.conformer.local ens-high.conformer.local
  ```

## 6. Trust the Caddy CA

Caddy serves `tls internal`. Trust its root on each client so Terraform accepts
the HTTPS endpoint — the root is exported at
[`compose/caddy-root.crt`](../compose/caddy-root.crt) (or pull it from the
running Caddy).

### Skip the CA trust: real wildcard cert via DNS-01

A publicly-trusted cert removes the per-client trust step entirely — Terraform
accepts it natively. Because the registry is VPN-only (no public 80/443), the
only ACME challenge that works is **DNS-01**: it proves domain control through
your DNS provider's API, opening no ports.

The framework subdomains (`cis.<DOMAIN>`, …) require a **wildcard** cert, so the
domain's DNS must be at a provider Caddy can drive. Example with Cloudflare:

1. Use the Cloudflare-DNS build of Caddy — [`compose/caddy/Dockerfile`](../compose/caddy/Dockerfile)
   (`xcaddy build --with github.com/caddy-dns/cloudflare`); the compose `caddy`
   service already builds it.
2. Create a Cloudflare API token scoped to **Zone → DNS → Edit** for your zone.
3. In `compose/.env`:
   ```bash
   DOMAIN=example.com
   CADDY_GLOBAL=acme_dns cloudflare {env.CF_API_TOKEN}   # DNS-01 for all certs
   CADDY_SITE_TLS=                                        # empty: drop `tls internal`
   CF_API_TOKEN=<your-cloudflare-token>
   ```
4. `docker compose up -d` — Caddy obtains `*.example.com` + `example.com` from
   Let's Encrypt over DNS-01 and auto-renews. No public ports, no CA to trust.

Clients still resolve `*.example.com → 10.13.13.1` (the public record points at
the now-closed public IP; the tunnel needs the override — §5). The cert
validates by name regardless of which IP answers.

Other DNS providers: swap the `caddy-dns/<provider>` plugin in the Dockerfile and
the `cloudflare` token in `CADDY_GLOBAL`.

## 7. Verify

```bash
# Over the tunnel — works:
curl -s --resolve conformer.local:443:10.13.13.1 https://conformer.local/v1/catalog | jq .domain

# From any non-VPN host / the public IP — refused (nothing listens there):
curl -m 5 https://<server-public-ip>/v1/catalog        # connection refused / timeout
```

## Firewall (belt and braces)

`BIND_IP` already keeps the registry ports off the public interface. Add a
host firewall so only WireGuard is reachable publicly:

```bash
sudo ufw allow 51820/udp
sudo ufw deny  80/tcp
sudo ufw deny  443/tcp
sudo ufw deny  7070/tcp
sudo ufw enable
```

## Defense in depth

Keep `STATIC_TOKENS` (or OIDC) on **inside** the VPN — the tunnel controls *who
can reach* the registry; the token controls *which frameworks they may pull*.
`/v1/catalog` stays open (discovery) but is now only reachable by peers.

## Other VPN options

The same `BIND_IP` knob works with any VPN — bind to that VPN's interface IP:

- **Tailscale / Netbird** (WireGuard mesh, less ops): `BIND_IP=<tailscale 100.x IP>`,
  resolve names via MagicDNS. `tailscale serve` can replace Caddy's public ports
  entirely.
- **Cloud client-VPN** (AWS Client VPN / Azure P2S): run the stack in a private
  subnet with no public IP; `BIND_IP` = the private NIC address.
