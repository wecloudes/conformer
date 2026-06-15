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
TRANSFORMS_ROOT="${TRANSFORMS_ROOT:-$(dirname "${PATCHES_ROOT}")/transformations}"
FRAMEWORKS_ROOT="${FRAMEWORKS_ROOT:-$(dirname "${PATCHES_ROOT}")/frameworks}"

# Resolve a framework (FRAMEWORK != "none") to its transformation bundle via the
# manifest frameworks/<fw>.hcl (ADR-009). With a manifest, the framework is
# applied through the SAME composable-transformation engine as the ad-hoc path,
# and the legacy patches/<fw>/ packs are skipped. Without one, fall back to the
# legacy packs. Any explicit ad-hoc TRANSFORMATIONS are appended after the
# framework units.
MANIFEST="${FRAMEWORKS_ROOT}/${FRAMEWORK}.hcl"
USE_MANIFEST=""
if [ "${FRAMEWORK}" != "none" ] && [ -f "${MANIFEST}" ]; then
  fw_list="$(awk '/transformations[[:space:]]*=[[:space:]]*\[/{f=1} f{print} f&&/\]/{exit}' "${MANIFEST}" \
    | grep -oE '"[A-Za-z0-9_-]+"' | tr -d '"' | paste -sd, -)"
  if [ -n "${fw_list}" ]; then
    USE_MANIFEST=1
    TRANSFORMATIONS="${fw_list}${TRANSFORMATIONS:+,${TRANSFORMATIONS}}"
    echo "framework ${FRAMEWORK} -> transformations: ${fw_list}"
  fi
fi

WORK="$(mktemp -d)"
OUTPUT_DIR="${WORK}/patched"
cp -r "${SRC_DIR}" "${OUTPUT_DIR}"
cd "${OUTPUT_DIR}"

echo "=== [1/6] sanitize (sed + gitleaks) ==="
# AWS account-id / region sanitization rewrites hardcoded values to
# data.aws_caller_identity / data.aws_region. It is AWS-ONLY: applying it to a
# non-AWS module injects an aws_* data source the module has no provider for AND
# corrupts any 12-digit run in descriptions/examples (e.g. Azure GUIDs). Gate it
# on the module actually using the AWS provider.
if grep -rqiE 'provider[[:space:]]+"aws"|resource[[:space:]]+"aws_|data[[:space:]]+"aws_|hashicorp/aws' . 2>/dev/null; then
  find . -name '*.tf' -print0 | xargs -0 -r sed -i -E \
    's/[0-9]{12}/${data.aws_caller_identity.current.account_id}/g'
  find . -name '*.tf' -print0 | xargs -0 -r sed -i -E \
    's/(arn:aws:[a-z0-9-]*:)(us|eu|ap|sa|ca|me|af)-[a-z]+-[0-9]/\1${data.aws_region.current.name}/g'
else
  echo "  (non-AWS module — skipping AWS account-id/region sanitization)"
fi
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

# Legacy framework packs (patches/<fw>/...) — used ONLY when the framework has no
# manifest (USE_MANIFEST unset) and a framework was requested. With a manifest,
# the same content is applied through the transformation engine below, so running
# these too would double-apply.
if [ -z "${USE_MANIFEST}" ] && [ "${FRAMEWORK}" != "none" ]; then
  # Generic _default pack (all *.mptf.hcl), applied at the module root.
  if [ -f "${GENERIC_DIR}/rules.mptf.hcl" ]; then
    echo "  generic: ${FRAMEWORK}/_default"
    ( cd "${OUTPUT_DIR}" && mapotf transform -r --mptf-dir "${GENERIC_DIR}" )
  fi

  # Module-specific rules MIRROR the module's directory layout: a rules.mptf.hcl
  # at <module>/ runs at the module root; one at <module>/modules/db_instance/
  # runs inside OUTPUT_DIR/modules/db_instance. This is how HARD resource
  # overrides reach resources that live in local submodules (wrapper modules).
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
fi

# Composable transformations (framework-agnostic units). Selected ad hoc
# (e.g. ?transformation=tags,destroy) or expanded from a framework manifest
# above. TRANSFORMATIONS is a comma-separated list of unit names under
# TRANSFORMS_ROOT/<name>/. For each unit apply its _default rules (any module)
# then module-specific rules, mirroring the module dir layout. Order = list order.
if [ -n "${TRANSFORMATIONS:-}" ]; then
  _oifs="${IFS}"; IFS=','
  for tname in ${TRANSFORMATIONS}; do
    IFS="${_oifs}"
    tname="$(printf '%s' "${tname}" | tr -d '[:space:]')"
    [ -n "${tname}" ] || { IFS=','; continue; }
    tgeneric="${TRANSFORMS_ROOT}/${tname}/_default"
    tmodule="${TRANSFORMS_ROOT}/${tname}/${MODULE}"
    applied=0
    # A generic unit applies if its _default dir has ANY *.mptf.hcl (a unit may
    # ship several, e.g. aws-secure-defaults = aws-modules + aws-datasources).
    # mapotf --mptf-dir applies them all in one pass.
    if ls "${tgeneric}"/*.mptf.hcl >/dev/null 2>&1; then
      echo "  transformation(generic): ${tname}/_default"
      ( cd "${OUTPUT_DIR}" && mapotf transform -r --mptf-dir "${tgeneric}" )
      applied=1
    fi
    if [ -d "${tmodule}" ]; then
      find "${tmodule}" -name 'rules.mptf.hcl' | sort | while read -r rf; do
        ruledir="$(dirname "${rf}")"
        rel="${ruledir#"${tmodule}"}"; rel="${rel#/}"        # "" or "modules/<sub>"
        tgt="${OUTPUT_DIR}${rel:+/${rel}}"
        if [ -d "${tgt}" ]; then
          echo "  transformation: ${tname}/${MODULE}/${rel:-.} -> ${rel:-(root)}"
          ( cd "${tgt}" && mapotf transform -r --mptf-dir "${ruledir}" )
        else
          echo "  skip ${tname}/${rel} (not present in this module)"
        fi
      done
      applied=1
    fi
    [ "${applied}" -eq 1 ] || echo "  WARN: transformation '${tname}' has no _default and no rules for module '${MODULE}' — nothing applied"
    IFS=','
  done
  IFS="${_oifs}"
fi

find . -name '*.tf.mptfbackup' -delete

echo "=== [4/6] advisory toggles + metadata ==="
# Advisory toggles (patch.hcl) from each applied transformation unit (_default +
# module dir). These are the source of the per-framework S3 toggle variables now
# that the framework S3 checks live in aws-s3-checks-<fw> units.
if [ -n "${TRANSFORMATIONS:-}" ]; then
  _oifs="${IFS}"; IFS=','
  for tname in ${TRANSFORMATIONS}; do
    IFS="${_oifs}"
    tname="$(printf '%s' "${tname}" | tr -d '[:space:]')"
    [ -n "${tname}" ] || { IFS=','; continue; }
    for d in "${TRANSFORMS_ROOT}/${tname}/_default" "${TRANSFORMS_ROOT}/${tname}/${MODULE}"; do
      if [ -f "${d}/patch.hcl" ]; then
        echo "# === Toggles: ${tname} ($(basename "${d}")) ===" >> _compliance.tf
        cat "${d}/patch.hcl" >> _compliance.tf
      fi
    done
    IFS=','
  done
  IFS="${_oifs}"
fi
# Legacy framework toggles — only when not using a manifest.
if [ -z "${USE_MANIFEST}" ] && [ "${FRAMEWORK}" != "none" ]; then
  for d in "${GENERIC_DIR}" "${MODULE_DIR}"; do
    if [ -f "${d}/patch.hcl" ]; then
      echo "# === Compliance toggles: ${FRAMEWORK} ($(basename "${d}")) ===" >> _compliance.tf
      cat "${d}/patch.hcl" >> _compliance.tf
    fi
  done
fi
# Framework metadata only when a framework was applied. The no-framework path
# (FRAMEWORK=none, ad-hoc transformations) skips it.
if [ "${FRAMEWORK}" != "none" ]; then
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
fi

# Record the exact transformation set applied (framework-expanded or ad hoc).
if [ -n "${TRANSFORMATIONS:-}" ]; then
  cat >> _compliance.tf <<EOF

variable "conformer_transformations" {
  type        = string
  default     = "${TRANSFORMATIONS}"
  description = "Composable transformations applied to this module (comma-separated)"
}
EOF
fi

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
