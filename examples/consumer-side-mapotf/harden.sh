#!/usr/bin/env bash
# Model B — harden an upstream module locally with mapotf, no registry / fork.
#
#   ./harden.sh [framework] [module-version]
#   ./harden.sh cis_v600 5.11.0
#
# Flow:  fetch upstream -> mapotf transform (in place) -> terraform plan
#        -> plan-gate -> mapotf reset (restore upstream).
set -euo pipefail

FRAMEWORK="${1:-cis_v600}"
VERSION="${2:-5.11.0}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${HERE}/../.." && pwd)"
UPSTREAM="${HERE}/upstream"

command -v mapotf >/dev/null || { echo "mapotf not installed: github.com/Azure/mapotf"; exit 1; }
[ -f "${REPO_ROOT}/frameworks/${FRAMEWORK}.hcl" ] || { echo "no framework manifest ${FRAMEWORK}"; exit 1; }

# 1. Fetch upstream module into ./upstream (no fork — a transient local copy).
if [ ! -d "${UPSTREAM}" ]; then
  echo "=== fetching terraform-aws-s3-bucket v${VERSION} ==="
  git clone --depth 1 --branch "v${VERSION}" \
    https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git "${UPSTREAM}"
  rm -rf "${UPSTREAM}/.git"
fi

# 2. Apply the SAME transformation units the registry pipeline uses — but right
#    here. apply-transforms.sh expands the framework manifest and runs mapotf for
#    each unit (generic _default + the s3-bucket bindings) against the checkout.
echo "=== apply transformations (${FRAMEWORK}) ==="
"${REPO_ROOT}/scripts/apply-transforms.sh" "${REPO_ROOT}" "${UPSTREAM}" s3-bucket "${FRAMEWORK}"

# 3. Plan against the patched local module.
echo "=== terraform plan ==="
( cd "${HERE}" && terraform init -input=false >/dev/null && terraform plan -out tfplan )

# 4. Plan-time gate (slide 29 layer 2).
echo "=== plan-gate ==="
( cd "${HERE}" && "${REPO_ROOT}/scripts/plan-gate.sh" tfplan ) || GATE_FAILED=1

# 5. Restore upstream so the checkout is pristine for the next run.
echo "=== mapotf reset ==="
( cd "${UPSTREAM}" && mapotf reset ) || find "${UPSTREAM}" -name '*.tf.mptfbackup' -exec sh -c 'mv "$1" "${1%.mptfbackup}"' _ {} \;

exit "${GATE_FAILED:-0}"
