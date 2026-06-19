#!/usr/bin/env bash
# Generate a WireGuard peer (a "user") for the conformer registry VPN, register
# it on the server live + persisted, and emit the client's wg0.conf.
#
# Run on the SERVER (the host running the stack), as root.
#
#   sudo ENDPOINT=<server-public-ip>:51820 ./add-peer.sh laptop
#   sudo ENDPOINT=1.2.3.4:51820 ./add-peer.sh ci-runner 10.13.13.7
#
# Hand the printed <name>.conf to that user; they drop it at /etc/wireguard/wg0.conf
# and run `wg-quick up wg0`. The peer's private key never leaves their config.
set -euo pipefail

WG_IFACE=${WG_IFACE:-wg0}
WG_CONF=${WG_CONF:-/etc/wireguard/${WG_IFACE}.conf}
SUBNET=${SUBNET:-10.13.13}                 # /24 the tunnel uses
ENDPOINT=${ENDPOINT:?set ENDPOINT=<server-public-ip>:51820}

name=${1:?usage: add-peer.sh <name> [client-ip]}
ip=${2:-}

[ -f "$WG_CONF" ] || { echo "no $WG_CONF — set up the WireGuard server first (docs/07)"; exit 1; }
command -v wg >/dev/null || { echo "wireguard-tools not installed"; exit 1; }

# Server public key, derived from the [Interface] PrivateKey in wg0.conf.
srv_priv=$(sed -n 's/^[[:space:]]*PrivateKey[[:space:]]*=[[:space:]]*//p' "$WG_CONF" | head -1)
[ -n "$srv_priv" ] || { echo "no PrivateKey in $WG_CONF"; exit 1; }
srv_pub=$(printf '%s' "$srv_priv" | wg pubkey)

# Auto-assign the next free .X if no IP was given (server is .1).
if [ -z "$ip" ]; then
  last=$(grep -oE "${SUBNET//./\\.}\.[0-9]+" "$WG_CONF" | awk -F. '{print $4}' | sort -n | tail -1)
  ip="${SUBNET}.$(( ${last:-1} + 1 ))"
fi
grep -q "AllowedIPs = ${ip}/32" "$WG_CONF" && { echo "ip $ip already used"; exit 1; }

# Client keypair (generated here; private key goes only into the client config).
cpriv=$(wg genkey)
cpub=$(printf '%s' "$cpriv" | wg pubkey)

# Register on the running interface (live) + persist to wg0.conf (next boot).
wg set "$WG_IFACE" peer "$cpub" allowed-ips "${ip}/32"
cat >> "$WG_CONF" <<EOF

[Peer]
# ${name}
PublicKey = ${cpub}
AllowedIPs = ${ip}/32
EOF

# Emit the client config.
out="./${name}.conf"
umask 077
cat > "$out" <<EOF
[Interface]
Address = ${ip}/32
PrivateKey = ${cpriv}
# DNS = ${SUBNET}.1   # uncomment if you run dnsmasq on the server for *.conformer.local

[Peer]
PublicKey = ${srv_pub}
Endpoint = ${ENDPOINT}
AllowedIPs = ${SUBNET}.0/24
PersistentKeepalive = 25
EOF

echo "peer '${name}' added at ${ip} -> ${out}"
command -v qrencode >/dev/null && { echo "scan to import on mobile:"; qrencode -t ansiutf8 < "$out"; }
