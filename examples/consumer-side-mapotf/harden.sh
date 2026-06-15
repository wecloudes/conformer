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
RULES_DIR="${REPO_ROOT}/patches/${FRAMEWORK}/s3-bucket"
UPSTREAM="${HERE}/upstream"

command -v mapotf >/dev/null || { echo "mapotf not installed: github.com/Azure/mapotf"; exit 1; }
[ -f "${RULES_DIR}/rules.mptf.hcl" ] || { echo "no rules for framework ${FRAMEWORK}"; exit 1; }

# 1. Fetch upstream module into ./upstream (no fork — a transient local copy).
if [ ! -d "${UPSTREAM}" ]; then
  echo "=== fetching terraform-aws-s3-bucket v${VERSION} ==="
  git clone --depth 1 --branch "v${VERSION}" \
    https://github.com/terraform-aws-modules/terraform-aws-s3-bucket.git "${UPSTREAM}"
  rm -rf "${UPSTREAM}/.git"
fi

# 2. Apply the SAME mapotf rules the registry pipeline uses — but right here.
echo "=== mapotf transform (${FRAMEWORK}) ==="
( cd "${UPSTREAM}" && mapotf transform -r --mptf-dir "${RULES_DIR}" )

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
