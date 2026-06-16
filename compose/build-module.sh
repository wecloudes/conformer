#!/usr/bin/env bash
# Runs INSIDE the builder container (the registry-api image, which bundles the
# patch toolkit). Fetches an upstream registry module, hardens it via
# scripts/patch-module.sh, and uploads the zip via `registry-api upload`
# (minio-go SDK — no AGPL mc).
#
#   build-module.sh <framework> <module> <version> [namespace] [provider]
#   build-module.sh cis_v600 s3-bucket 5.11.0
set -euo pipefail

FRAMEWORK="${1:?framework e.g. cis_v600}"
MODULE="${2:?module e.g. s3-bucket}"
VERSION="${3:?version e.g. 5.11.0}"
NAMESPACE="${4:-terraform-aws-modules}"
PROVIDER="${5:-aws}"

REPO=/repo
UPSTREAM="${UPSTREAM_REGISTRY:-registry.terraform.io}"
WORK="/tmp/build/${FRAMEWORK}-${MODULE}-${VERSION}"
ZIP="${WORK}/module.zip"

rm -rf "${WORK}"; mkdir -p "${WORK}"

# Fully-qualified registry source so `tofu get` pulls from the Terraform registry.
echo "### fetch ${UPSTREAM}/${NAMESPACE}/${MODULE}/${PROVIDER} @ ${VERSION} (tofu get)"
cd "${WORK}"
cat > main.tf <<EOF
module "m" {
  source  = "${UPSTREAM}/${NAMESPACE}/${MODULE}/${PROVIDER}"
  version = "${VERSION}"
}
EOF
tofu get
SRC="$(realpath "$(jq -r '.Modules[] | select(.Key=="m") | .Dir' .terraform/modules/modules.json)")"

echo "### patch (layered pipeline)"
"${REPO}/scripts/patch-module.sh" "${SRC}" "${REPO}/patches" "${FRAMEWORK}" "${MODULE}" "${VERSION}" "${ZIP}"

echo "### upload to MinIO (registry-api upload)"
KEY="${NAMESPACE}/${MODULE}/${PROVIDER}/${FRAMEWORK}/${VERSION}.zip"
registry-api upload "${ZIP}" "${KEY}"
echo "### done: ${MINIO_BUCKET}/${KEY}"
