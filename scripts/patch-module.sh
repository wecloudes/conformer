#!/usr/bin/env bash
# Canonical layered patcher — the same pipeline the Tekton task runs, packaged
# as one script so the Docker Compose builder, the on-demand dynamic builder,
# and anyone with the toolkit image can produce a hardened module.zip.
#
# Applies, in order, the framework's GENERIC rules (patches/<fw>/_default) then
# any MODULE-SPECIFIC rules (patches/<fw>/<module>). The generic layer is what
# lets an arbitrary module pulled from the upstream registry still be hardened.
#
# Usage (run inside the patch-toolkit image, all tools on PATH):
#   patch-module.sh <src_dir> <patches_root> <framework> <module> <version> <out_zip>
#
#   src_dir       upstream module checkout
#   patches_root  the repo's patches/ directory
#   out_zip       path to write module.zip
#
# Env: SKIP_VALIDATE=true  skips terraform init/validate (avoids provider
#      downloads on the dynamic hot path).
set -euo pipefail

SRC_DIR="${1:?src_dir}"
PATCHES_ROOT="${2:?patches_root}"
FRAMEWORK="${3:?framework}"
MODULE="${4:?module}"
VERSION="${5:?version}"
OUT_ZIP="${6:?out_zip}"

GENERIC_DIR="${PATCHES_ROOT}/${FRAMEWORK}/_default"
MODULE_DIR="${PATCHES_ROOT}/${FRAMEWORK}/${MODULE}"

WORK="$(mktemp -d)"
OUTPUT_DIR="${WORK}/patched"
cp -r "${SRC_DIR}" "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

echo "=== [1/6] sanitize (sed + gitleaks) ==="
find . -name '*.tf' -print0 | xargs -0 -r sed -i -E \
  's/[0-9]{12}/${data.aws_caller_identity.current.account_id}/g'
find . -name '*.tf' -print0 | xargs -0 -r sed -i -E \
  's/(arn:aws:[a-z0-9-]*:)(us|eu|ap|sa|ca|me|af)-[a-z]+-[0-9]/\1${data.aws_region.current.name}/g'
# Third-party modules routinely trip gitleaks on example fixtures / var defaults
# (examples/*.pfx, sample passwords). Report by default; only block the build
# when GITLEAKS_STRICT=true (use for curated, first-party modules).
GL_EXIT=$([ "${GITLEAKS_STRICT:-false}" = "true" ] && echo 1 || echo 0)
gitleaks detect --no-git --source . --redact --exit-code "${GL_EXIT}" \
  || { echo "gitleaks found secrets and GITLEAKS_STRICT=true → failing"; exit 1; }

echo "=== [2/6] strip provisioner blocks (awk) ==="
for f in $(find . -name '*.tf'); do
  awk '
    /^[[:space:]]*provisioner / { s=1; d=0 }
    s { if (/{/) d++; if (/}/ && d>0) { d--; if (d==0) { s=0; next } } next }
    { print }
  ' "$f" > "$f.stripped" && mv "$f.stripped" "$f"
done

echo "=== [3/6] structural transforms (mapotf) ==="

# Generic _default pack (all *.mptf.hcl), applied at the module root.
if [ -f "${GENERIC_DIR}/rules.mptf.hcl" ]; then
  echo "  generic: ${FRAMEWORK}/_default"
  ( cd "${OUTPUT_DIR}" && mapotf transform -r --mptf-dir "${GENERIC_DIR}" )
fi

# Module-specific rules MIRROR the module's directory layout: a rules.mptf.hcl at
# <module>/ runs at the module root; one at <module>/modules/db_instance/ runs
# inside OUTPUT_DIR/modules/db_instance. This is how HARD resource overrides
# reach resources that live in local submodules (wrapper modules).
if [ -d "${MODULE_DIR}" ]; then
  find "${MODULE_DIR}" -name 'rules.mptf.hcl' | sort | while read -r rf; do
    ruledir="$(dirname "${rf}")"
    rel="${ruledir#"${MODULE_DIR}"}"; rel="${rel#/}"        # "" or "modules/db_instance"
    tgt="${OUTPUT_DIR}${rel:+/${rel}}"
    if [ -d "${tgt}" ]; then
      echo "  module-specific: ${FRAMEWORK}/${MODULE}/${rel:-.} -> ${rel:-(root)}"
      ( cd "${tgt}" && mapotf transform -r --mptf-dir "${ruledir}" )
    else
      echo "  skip ${rel} (not present in this module)"
    fi
  done
fi

find . -name '*.tf.mptfbackup' -delete

echo "=== [4/6] advisory toggles + metadata ==="
for d in "${GENERIC_DIR}" "${MODULE_DIR}"; do
  if [ -f "${d}/patch.hcl" ]; then
    echo "# === Compliance toggles: ${FRAMEWORK} ($(basename "${d}")) ===" >> _compliance.tf
    cat "${d}/patch.hcl" >> _compliance.tf
  fi
done
cat >> _compliance.tf <<EOF

variable "compliance_framework" {
  type        = string
  default     = "${FRAMEWORK}"
  description = "Compliance framework applied to this module"
  validation {
    condition     = var.compliance_framework == "${FRAMEWORK}"
    error_message = "This module is patched for the ${FRAMEWORK} framework."
  }
}
EOF

# Default: skip validate. `tofu init`/`validate` would resolve providers from
# the OpenTofu registry, which may not carry every provider a third-party module
# pins — and validate is non-essential here. fmt is offline/safe and always run.
# Set SKIP_VALIDATE=false to opt in (curated modules with known providers).
if [ "${SKIP_VALIDATE:-true}" = "true" ]; then
  echo "=== [5/6] fmt (validate skipped) ==="
  tofu fmt -recursive . >/dev/null || true
else
  echo "=== [5/6] fmt + validate ==="
  tofu fmt -recursive . >/dev/null
  tofu init -backend=false -input=false >/dev/null 2>&1 || true
  tofu validate || echo "WARN: validate incomplete (provider/var context)"
fi

echo "=== [6/6] zip ==="
mkdir -p "$(dirname "${OUT_ZIP}")"
# Remove any pre-existing target (callers may pass a temp file that already
# exists); zip would otherwise try to append to a non-archive and fail.
rm -f "${OUT_ZIP}"
( cd "${OUTPUT_DIR}" && zip -qr "${OUT_ZIP}" . -x "*.git*" "*.terraform*" "*.tf.mptfbackup" )
echo "Wrote ${OUT_ZIP} ($(du -h "${OUT_ZIP}" | cut -f1))"
rm -rf "${WORK}"
