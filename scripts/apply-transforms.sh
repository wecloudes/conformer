#!/usr/bin/env bash
# Apply transformation units to a module dir IN PLACE — the Model B (consumer-
# side) counterpart of patch-module.sh's structural layer. No fetch, no zip: just
# run mapotf for the selected units against an existing checkout, so the caller
# can plan against the hardened copy and `mapotf reset` afterwards.
#
#   apply-transforms.sh <repo_root> <target_dir> <module> <framework>
#   apply-transforms.sh <repo_root> <target_dir> <module> -t <unit,unit,...>
#
#   repo_root   the conformer repo (holds transformations/ and frameworks/)
#   target_dir  the module checkout to transform in place
#   module      upstream module name (selects <unit>/<module>/ bindings)
set -euo pipefail

REPO_ROOT="${1:?repo_root}"
TARGET="${2:?target_dir}"
MODULE="${3:?module}"
SEL="${4:?framework name or -t}"

TRANSFORMS_ROOT="${REPO_ROOT}/transformations"

if [ "${SEL}" = "-t" ]; then
  UNITS="${5:?unit list after -t}"
else
  MANIFEST="${REPO_ROOT}/frameworks/${SEL}.hcl"
  [ -f "${MANIFEST}" ] || { echo "no framework manifest ${MANIFEST}" >&2; exit 1; }
  UNITS="$(awk '/transformations[[:space:]]*=[[:space:]]*\[/{f=1} f{print} f&&/\]/{exit}' "${MANIFEST}" \
    | grep -oE '"[A-Za-z0-9_-]+"' | tr -d '"' | paste -sd, -)"
fi

_oifs="${IFS}"; IFS=','
for u in ${UNITS}; do
  IFS="${_oifs}"
  u="$(printf '%s' "${u}" | tr -d '[:space:]')"
  [ -n "${u}" ] || { IFS=','; continue; }
  for d in "${TRANSFORMS_ROOT}/${u}/_default" "${TRANSFORMS_ROOT}/${u}/${MODULE}"; do
    if ls "${d}"/*.mptf.hcl >/dev/null 2>&1; then
      echo "  apply ${u} ($(basename "${d}"))"
      ( cd "${TARGET}" && mapotf transform -r --mptf-dir "${d}" )
    fi
  done
  IFS=','
done
IFS="${_oifs}"
