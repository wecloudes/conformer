#!/usr/bin/env bash
# On-demand builder — pulls ANY module from the upstream Terraform registry,
# applies the framework's generic + module-specific patches, writes module.zip.
# Invoked by the registry API on a cache miss (DYNAMIC_BUILD=true); the API
# uploads the resulting zip via the minio-go SDK.
#
#   build-dynamic.sh <namespace> <name> <provider> <version> <framework>
#   build-dynamic.sh Azure avm-res-automation-automationaccount azurerm 0.2.0 cis_v600
#
# Env: PATCHES_ROOT, UPSTREAM_REGISTRY, OUT_ZIP (where to write the zip)
set -euo pipefail

NS="${1:?namespace}"
NAME="${2:?name}"
PROVIDER="${3:?provider}"
VERSION="${4:?version}"
FRAMEWORK="${5:?framework}"

PATCHES_ROOT="${PATCHES_ROOT:-/app/patches}"
UPSTREAM="${UPSTREAM_REGISTRY:-registry.terraform.io}"
OUT_ZIP="${OUT_ZIP:?OUT_ZIP path required}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Source allow-list: comma-separated <namespace>/<name> globs. Empty = allow any
# (default). When set, only matching upstream modules may be dynamically built —
# stops the registry being used to pull and serve arbitrary third-party modules.
#   ALLOWED_MODULES="terraform-aws-modules/*,Azure/avm-res-*"
ALLOWED_MODULES="${ALLOWED_MODULES:-}"
if [ -n "${ALLOWED_MODULES}" ]; then
  allowed=0
  oldifs="${IFS}"; IFS=','
  for pat in ${ALLOWED_MODULES}; do
    pat="$(printf '%s' "${pat}" | tr -d '[:space:]')"
    case "${NS}/${NAME}" in ${pat}) allowed=1; break;; esac
  done
  IFS="${oldifs}"
  if [ "${allowed}" -ne 1 ]; then
    echo "ERROR: ${NS}/${NAME} is not in ALLOWED_MODULES (${ALLOWED_MODULES})" >&2
    exit 1
  fi
fi

WORK="$(mktemp -d)"
cd "${WORK}"

# ALWAYS fully-qualify the registry host. OpenTofu's default module registry is
# registry.opentofu.org, which does NOT mirror every module (e.g. Azure AVM).
# Naming the host forces the fetch to come from the Terraform registry, so
# `tofu get` resolves the same modules `terraform get` would.
ADDR="${UPSTREAM}/${NS}/${NAME}/${PROVIDER}"

echo "### fetch ${ADDR} @ ${VERSION} (tofu get)"
cat > main.tf <<EOF
module "m" {
  source  = "${ADDR}"
  version = "${VERSION}"
}
EOF
# `tofu get` downloads MODULES only (no providers) into .terraform/modules.
tofu get
DIR="$(jq -r '.Modules[] | select(.Key=="m") | .Dir' .terraform/modules/modules.json)"
[ -n "${DIR}" ] && [ -d "${DIR}" ] || { echo "ERROR: module fetch failed"; exit 1; }
DIR="$(realpath "${DIR}")"

echo "### patch (generic ${FRAMEWORK}/_default + ${FRAMEWORK}/${NAME})"
SKIP_VALIDATE=true "${SCRIPT_DIR}/patch-module.sh" \
  "${DIR}" "${PATCHES_ROOT}" "${FRAMEWORK}" "${NAME}" "${VERSION}" "${OUT_ZIP}"

rm -rf "${WORK}"
echo "### built -> ${OUT_ZIP}"
