# Caddy with the Cloudflare DNS plugin, for ACME DNS-01 wildcard certs.
# The stock caddy image has no DNS providers compiled in, so a wildcard
# Let's Encrypt cert (needed for the framework subdomains) is impossible
# without this build. DNS-01 needs no public ports — fits the VPN-only deploy.
FROM caddy:builder-alpine AS build
RUN xcaddy build --with github.com/caddy-dns/cloudflare

FROM caddy:alpine
COPY --from=build /usr/bin/caddy /usr/bin/caddy
