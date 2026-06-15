# Conformer

**Conform any Terraform module to a compliance framework — without forking it.**

Conformer is a framework-aware Terraform/OpenTofu module registry that transforms
upstream modules to a compliance framework (CIS, ISO 27001, SOC 2, …) on the fly.
Point Terraform at a framework subdomain and Conformer fetches the upstream
module, applies the framework's structural patches, and serves the hardened
result — either pre-built or patched on demand. Inspired by
[compliance.tf](https://compliance.tf), built entirely on open-source components
(permissive / weak-copyleft only — see [LICENSES.md](LICENSES.md)).

> **New here?** Start with [`docs/`](docs/): how modules are hardened
> ([transformation techniques](docs/01-transformation-techniques.md)), the
> delivery strategies ([enforcement models](docs/02-enforcement-models.md)), how
> to consume them ([consuming guide](docs/03-consuming.md)), and how the registry
> patches *any* upstream module on demand
> ([dynamic patching](docs/04-dynamic-patching.md)).

## Architecture

```
*.conformer.local (wildcard DNS)
        │
  ┌─────▼──────┐
  │ Nginx      │
  │ Ingress    │
  └─────┬──────┘
        │
  ┌─────┼──────────────────┐
  │     │                  │
  ▼     ▼                  ▼
Registry  Keycloak       MinIO
API       (OAuth2)       (S3-compat)
  │
  ▼
Tekton Pipelines
(build compliance modules)
```

### Components

| Component | Tool | Purpose |
|---|---|---|
| Registry API | Custom Go service | Terraform Module Registry Protocol v1 |
| Auth | Keycloak (Bitnami chart) | OAuth2/OIDC, framework entitlements |
| Storage | MinIO (Bitnami chart) | S3-compatible module zip storage |
| Build | Tekton Pipelines | Patch upstream modules, upload to MinIO |
| Ingress | nginx-ingress | Wildcard subdomain routing |
| TLS | cert-manager | Wildcard certificate management |

### How it works

1. Framework subdomains (`cis.conformer.local`, `iso27001.conformer.local`) all resolve to the same ingress
2. The Registry API extracts the framework from the `Host` header
3. Validates the Bearer token against Keycloak JWKS, checks framework entitlement
4. Returns a presigned MinIO URL for the compliance-patched module zip
5. Terraform downloads and uses the patched module transparently

## Module transformation

Compliance hardening is real structural HCL rewriting, not just appended
documentation. The build applies the DIY transformation playbook in layers:

| Layer | Tool | What it does |
|---|---|---|
| Sanitization | `sed` + `gitleaks` | strip hardcoded account IDs / regions, fail on leaked secrets |
| Block removal | `awk` brace-counter | strip injected `provisioner` / `local-exec` blocks |
| Structural | `mapotf` + `hcledit` | inject `lifecycle { prevent_destroy }`, override insecure attributes (e.g. force public-access flags shut), add plan-time `check` blocks |
| Advisory toggles | `variable { validation }` | source-time opt-out flags per control |
| Plan-time gate | `terraform show -json` + `jq` | assert caller config satisfies controls at plan time (`scripts/plan-gate.sh`) |

The structural layer is driven by per-framework
[`mapotf`](https://github.com/Azure/mapotf) rules at
`patches/<framework>/<module>/rules.mptf.hcl`. All tools ship in one image
built from `patches/Dockerfile.patch-toolkit` (set as `tekton.patchImage`).

### Two ways to patch

- **Model A — registry (this chart):** transform runs once in Tekton, the
  hardened zip is stored in MinIO and served via the Registry Protocol.
  Consumers use plain `terraform`; enforcement is mandatory and server-gated.
- **Model B — direct (no registry, no fork):** the *same* `rules.mptf.hcl` are
  applied on the consumer side at plan time with `mapotf transform`. Zero server
  infra, but opt-in (a convenience, not a control). See
  [`examples/consumer-side-mapotf/`](examples/consumer-side-mapotf/).

## Quick start (Docker Compose)

Prefer a single host over Kubernetes? [`compose/`](compose/) runs the whole
registry with Docker Compose — static-token auth (no Keycloak), MinIO, a Caddy
wildcard proxy, and a one-shot builder that replaces Tekton:

```bash
cd compose
cp .env.example .env
docker compose up -d
./build.sh cis_v600 s3-bucket 5.11.0
```

See [`compose/README.md`](compose/README.md) for DNS/TLS setup and consuming.
The Kubernetes/Helm path below is for production / multi-tenant deployments.

## Prerequisites

- Kubernetes cluster (1.27+)
- Helm 3.12+
- nginx-ingress controller installed
- cert-manager installed
- Tekton Pipelines installed

```bash
# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true

# nginx-ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace

# Tekton Pipelines
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/latest/release.yaml
```

## Installation

### 1. Build the Registry API image

```bash
cd registry-api/
docker build -t conformer-api:latest .

# If using a remote registry:
docker tag conformer-api:latest your-registry.com/conformer-api:latest
docker push your-registry.com/conformer-api:latest
```

### 2. Update values

Edit `charts/conformer/values.yaml`:

```yaml
domain: compliance.yourdomain.com

registryApi:
  image:
    repository: your-registry.com/conformer-api
    tag: latest

keycloak:
  auth:
    adminPassword: "your-secure-password"

minio:
  auth:
    rootPassword: "your-secure-password"
```

### 3. Install the Helm chart

```bash
cd charts/conformer/
helm dependency update .
helm install compliance . \
  --namespace compliance \
  --create-namespace
```

### 4. Configure DNS

Point `*.compliance.yourdomain.com` to your ingress controller's external IP:

```bash
# Get the ingress IP
kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

# Create wildcard DNS record:
# *.compliance.yourdomain.com -> <ingress-ip>
```

For local development, add entries to `/etc/hosts`:
```
127.0.0.1 cis.conformer.local iso27001.conformer.local soc2.conformer.local auth.conformer.local
```

## Usage

### Authenticate with the registry

```bash
terraform login cis.conformer.local
# Opens browser -> Keycloak login -> token saved to ~/.terraform.d/credentials.tfrc.json
```

### Use a compliance module

```hcl
# main.tf
module "s3_bucket" {
  source  = "cis.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"

  bucket = "my-compliant-bucket"

  # These are enforced by CIS patches — setting to false will fail at plan time
  cis_enforce_encryption   = true
  cis_enforce_ssl_only     = true
  cis_block_public_access  = true
  cis_enforce_versioning   = true
  cis_enforce_logging      = true
}
```

```bash
terraform init   # Downloads the CIS-patched module from the registry
terraform plan   # Compliance validations run at plan time
```

### Switch frameworks

Same module, different framework — just change the subdomain:

```hcl
# ISO 27001 variant
module "s3_bucket" {
  source  = "iso27001.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"
  # ...
}

# SOC 2 variant
module "s3_bucket" {
  source  = "soc2.conformer.local/terraform-aws-modules/s3-bucket/aws"
  version = "5.11.0"
  # ...
}
```

## Building Compliance Modules

### Manual PipelineRun

```bash
kubectl create -f - <<EOF
apiVersion: tekton.dev/v1
kind: PipelineRun
metadata:
  generateName: build-s3-bucket-
  namespace: compliance
spec:
  pipelineRef:
    name: compliance-build-module
  params:
    - name: module-namespace
      value: "terraform-aws-modules"
    - name: module-name
      value: "s3-bucket"
    - name: module-provider
      value: "aws"
    - name: module-version
      value: "5.11.0"
  workspaces:
    - name: shared-workspace
      volumeClaimTemplate:
        spec:
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 5Gi
    - name: patches-workspace
      configMap:
        name: compliance-patches
EOF
```

### Adding new modules

1. Create patch files in `patches/{framework}/{module-name}/patch.hcl`
2. Update the CronJob module list in `values.yaml` or the trigger ConfigMap
3. Run the pipeline manually or wait for the next scheduled check

### Adding new frameworks

1. Add framework to `values.yaml` under `frameworks`
2. Add Keycloak role `framework:{name}` to the realm configuration
3. Create patch directory `patches/{framework}/`
4. Add pipeline tasks in `pipeline.yaml` (or use dynamic approach)

## Project Structure

```
conformer/
├── docs/                           # Strategy + technique + consuming guides
├── compose/                        # Docker Compose stack (simple, single-host)
├── charts/conformer/     # Helm umbrella chart
│   ├── Chart.yaml                  # Bitnami keycloak + minio as deps
│   ├── values.yaml                 # All configuration
│   └── templates/
│       ├── registry-*.yaml         # Custom Registry API resources
│       ├── ingress.yaml            # Wildcard subdomain routing
│       ├── cert-*.yaml             # cert-manager resources
│       ├── keycloak-realm-*.yaml   # Keycloak realm import
│       └── tekton/                 # Pipeline, tasks, triggers
├── registry-api/                   # Go service (TF Registry Protocol)
│   ├── main.go
│   ├── go.mod
│   └── Dockerfile
├── patches/                        # Compliance patches per framework
│   ├── Dockerfile.patch-toolkit    # mapotf+hcledit+terraform+jq+gitleaks image
│   ├── cis_v600/
│   │   ├── _default/rules.mptf.hcl # GENERIC rules — applied to ANY module
│   │   └── s3-bucket/
│   │       ├── rules.mptf.hcl      # module-specific structural transforms
│   │       └── patch.hcl           # advisory validation toggles (source-time)
│   ├── iso27001/
│   └── soc2/
├── scripts/
│   ├── patch-module.sh             # canonical layered patcher (generic + specific)
│   ├── build-dynamic.sh            # on-demand: fetch upstream + patch + cache
│   └── plan-gate.sh                # plan-time jq compliance gate
└── examples/
    ├── consumer-side-mapotf/       # Model B: patch directly, no registry/fork
    └── terragrunt/                 # Terragrunt: tfr:// (A) + before_hook (B)
```

Terragrunt consumers: see [`examples/terragrunt/`](examples/terragrunt/) for
both the `tfr://` registry source (Model A) and the `before_hook` mapotf
approach (Model B).

### Build the patch toolkit image

```bash
docker build -f patches/Dockerfile.patch-toolkit \
  -t compliance-patch-toolkit:latest patches/
# push to your registry, then set tekton.patchImage in values.yaml
```
