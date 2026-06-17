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

## 4. Point the registry at the VPN interface

In `compose/.env`:

```bash
BIND_IP=10.13.13.1
# Presigned download URLs must use a VPN-reachable host (the S3 signature binds
# it — a localhost/public host would not resolve for the peer):
S3_PUBLIC_ENDPOINT=10.13.13.1:7070
```

Restart: `docker compose -f compose/docker-compose.yml up -d`. Confirm the ports
are no longer on `0.0.0.0`:

```bash
docker compose -f compose/docker-compose.yml ps   # ports show 10.13.13.1:443->443, etc.
ss -ltnp | grep -E ':443|:7070'                   # bound to 10.13.13.1, not 0.0.0.0
```

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
running Caddy). Alternatively switch Caddy to a real domain + DNS-01 cert.

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
