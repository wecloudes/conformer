# Build context is the REPO ROOT (so scripts/ and patches/ are available for
# dynamic, on-demand patching). In Compose: build.context: .. , dockerfile:
# registry-api/Dockerfile.

FROM golang:1.24-alpine AS gobuild
WORKDIR /app
COPY registry-api/go.mod registry-api/go.sum ./
RUN go mod download
COPY registry-api/ .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-s -w" -o /out/registry-api .
# graft (MPL-2.0) — no release binaries published, build from source.
RUN CGO_ENABLED=0 GOBIN=/out go install github.com/ms-henglu/graft@v0.2.0

# Final image carries the patch toolkit so the API can build modules on demand.
# Tool set mirrors patches/Dockerfile.patch-toolkit. All licenses are
# permissive/weak-copyleft (MPL/MIT/Apache) — no BUSL (Terraform) or bundled
# AGPL (mc): OpenTofu replaces Terraform, uploads go through the minio-go SDK.
FROM alpine:3.19
ARG OPENTOFU_VERSION=1.12.2
ARG MAPOTF_VERSION=0.1.4
ARG HCLEDIT_VERSION=0.2.17
ARG GITLEAKS_VERSION=8.30.1
# TARGETARCH is auto-populated by BuildKit to the build platform (amd64/arm64).
ARG TARGETARCH

RUN apk add --no-cache bash curl git jq gawk sed unzip zip ca-certificates

# OpenTofu (MPL-2.0) — replaces HashiCorp Terraform (BUSL-1.1).
RUN curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${OPENTOFU_VERSION}/tofu_${OPENTOFU_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin tofu
RUN curl -fsSL "https://github.com/minamijoyo/hcledit/releases/download/v${HCLEDIT_VERSION}/hcledit_${HCLEDIT_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin hcledit
RUN curl -fsSL "https://github.com/Azure/mapotf/releases/download/v${MAPOTF_VERSION}/mapotf_${MAPOTF_VERSION}_linux_${TARGETARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin mapotf && chmod +x /usr/local/bin/mapotf
RUN GL=$([ "${TARGETARCH}" = "arm64" ] && echo arm64 || echo x64); \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL}.tar.gz" \
    | tar -xz -C /usr/local/bin gitleaks

COPY --from=gobuild /out/registry-api /usr/local/bin/registry-api
COPY --from=gobuild /out/graft /usr/local/bin/graft
COPY scripts/ /app/scripts/
COPY patches/ /app/patches/
RUN chmod +x /app/scripts/*.sh

# tofu get / mapotf need a writable workdir; /tmp is fine.
WORKDIR /tmp
EXPOSE 8080
ENTRYPOINT ["registry-api"]
